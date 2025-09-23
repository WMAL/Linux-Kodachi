#!/usr/bin/env python
# -*- coding: utf-8 -*-
'''
Encrypt and decrypt files using AES encryption and a common
password. You can use it lock files before they are uploaded to
storage services like DropBox or Google Drive.

The password can be stored in a safe file, specified on the command
line or it can be manually entered each time the tool is run.

Here is how you would use this tool to encrypt a number of files using
a local, secure file. You can optionally specify the --lock switch but
since it is the default, it is not necessary.

   $ lock_files.py file1.txt file2.txt dir1 dir2
   Password: secret
   Re-enter password: secret

When the lock command is finished all of files will be locked (encrypted,
with a ".locked" extension).

You can lock the same files multiple times with different
passwords. Each time lock_files.py is run in lock mode, another
".locked" extension is appended. Each time it is run in unlock mode, a
".locked" extension is removed. Unlock mode is enabled by specifying
the --unlock option.

Of course, entering the password manually each time can be a challenge.
It is normally easier to create a read-only file that can be re-used.
Here is how you would do that.

   $ cat >password-file
   thisismysecretpassword
   EOF
   $ chmod 0600 password-file

You can now use the password file like this to lock and unlock a file.

   $ lock_files.py -p password-file file1.txt
   $ lock_files.py -p password-file --unlock file1.txt.locked

In decrypt mode, the tool walks through the specified files and
directories looking for files with the .locked extension and unlocks
(decrypts) them.

Here is how you would use this tool to decrypt a file, execute a
program and then re-encrypt it when the program exits.

   $ # the unlock operation removes the .locked extension
   $ lock_files.py -p ./password --unlock file1.txt.locked
   $ edit file1.txt
   $ lock_files.py -p ./password file1.txt

The tool checks each file to make sure that it is writeable before
processing. If any files is not writeable, the program reports an
error and exits unless you specify --warn in which case it
reports a warning that the file will be ignored and continues.

If you want to change a file in place you can use --inplace mode.
See the documentation for that option to get more information.

If you want to encrypt and decrypt files so that they can be
processed using openssl, you must use compatibility mode (-c).

Here is how you could encrypt a file using lock_files.py and
decrypt it using openssl.

   $ lock_files.py -P secret --lock file1.txt
   $ ls file1*
   file1.txt.locked
   $ openssl enc -aes-256-cbc -d -a -salt -pass pass:secret -in file1.txt.locked -out file1.txt

Here is how you could encrypt a file using openssl and then
decrypt it using lock_files.py.

   $ openssl enc -aes-256-cbc -e -a -salt -pass pass:secret -in file1.txt -out file1.txt.locked
   $ ls file1*
   file1.txt      file1.txt.locked
   $ lock_files.py -c -W -P secret --unlock file1.txt.locked
   $ ls file1*
   file1.txt

Note that you have to use the -W option to change errors to
warning because the file1.txt output file already exists.
'''
import argparse
import base64
import getpass
import hashlib
import inspect
import os
import subprocess
import sys
import threading

from threading import Thread, Lock, Semaphore

try:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    from cryptography.hazmat.backends import default_backend
except ImportError as exc:
    print('ERROR: Import failed, you may need to run "pip install cryptography".\n{:>7}{}'.format('', exc))
    sys.exit(1)

try:
    import Queue as queue  # python 2
except ImportError:
    import queue   # python3


# ================================================================
#
# Module scope variables.
#
# ================================================================
VERSION = '1.1.1'
th_mutex = Lock()  # mutex for thread IO
th_semaphore = None  # semapthore to limit max active threads
th_abort = False  # If true, abort all threads


# ================================================================
#
# Classes.
#
# ================================================================
class AESCipher:
    '''
    Class that provides an object to encrypt or decrypt a string
    or a file.

    CITATION: http://joelinoff.com/blog/?p=885
    '''
    def __init__(self, openssl=False, digest='md5', keylen=32, ivlen=16):
        '''
        Initialize the object.

        @param openssl  Operate identically to openssl.
        @param width    Width of the MIME encoded lines for encryption.
        @param digest   The digest used.
        @param keylen   The key length (32-256, 16-128, 8-64).
        @param ivlen    Length of the initialization vector.
        '''
        self.m_openssl = openssl
        self.m_openssl_prefix = b'Salted__'  # Hardcoded into openssl.
        self.m_openssl_prefix_len = len(self.m_openssl_prefix)
        self.m_digest = getattr(__import__('hashlib', fromlist=[digest]), digest)
        self.m_keylen = keylen
        self.m_ivlen = ivlen
        if keylen not in [8, 16, 32]:
            err('invalid keylen {}, must be 16, 24 or 32'.format(keylen))
        if openssl and ivlen != 16:
            err('invalid ivlen size {}, for openssl compatibility it must be 16'.format(ivlen))

    def encrypt(self, password, plaintext):
        '''
        Encrypt the plaintext using the password, optionally using an
        openssl compatible encryption algorithm.

        If it is run in openssl compatibility mode, it is the same as
        running openssl like this:

            $ openssl enc -aes-256-cbc -e -a -salt -pass pass:<password> -in plaintext

        @param password  The password.
        @param plaintext The plaintext to encrypt.
        @param msgdgst   The message digest algorithm.
        '''
        # Setup key and IV for both modes.
        if self.m_openssl:
            salt = os.urandom(self.m_ivlen - len(self.m_openssl_prefix))
            key, iv = self._get_key_and_iv(password, salt)
            if key is None or iv is None:
                return None
        else:
            # No 'Salted__' prefix.
            key = self._get_password_key(password)
            iv = os.urandom(self.m_ivlen)  # IV is the same as block size for CBC mode

        # Key
        key = self._encode(key)

        # Encrypt
        padded_plaintext = self._pkcs7_pad(plaintext, self.m_ivlen)
        backend = default_backend()
        cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=backend)
        encryptor = cipher.encryptor()
        ciphertext_binary = encryptor.update(padded_plaintext) + encryptor.finalize()

        # Finalize
        if self.m_openssl:
            # Make openssl compatible.
            # I first discovered this when I wrote the C++ Cipher class.
            # CITATION: http://projects.joelinoff.com/cipher-1.1/doxydocs/html/
            openssl_compatible = self.m_openssl_prefix + salt + ciphertext_binary
            ciphertext = base64.b64encode(openssl_compatible)
        else:
            ciphertext = base64.b64encode(iv + ciphertext_binary)

        return ciphertext

    def decrypt(self, password, ciphertext):
        '''
        Decrypt the ciphertext using the password, optionally using an
        openssl compatible decryption algorithm.

        If it was encrypted in openssl compatible mode, it is the same
        as running the following openssl decryption command:

            $ egrep -v '^#|^$' | openssl enc -aes-256-cbc -d -a -salt -pass pass:<password> -in ciphertext

        @param password   The password.
        @param ciphertext The ciphertext to decrypt.
        @returns the decrypted data.
        '''
        if self.m_openssl:
            # Base64 decode
            ciphertext_prefixed_binary = base64.b64decode(ciphertext)
            if ciphertext_prefixed_binary[:self.m_openssl_prefix_len] != self.m_openssl_prefix:
                err('bad header, cannot decrypt')
            salt = ciphertext_prefixed_binary[self.m_openssl_prefix_len:self.m_ivlen]  # get the salt

            # Now create the key and iv.
            key, iv = self._get_key_and_iv(password, salt)
            if key is None or iv is None:
                return None
        else:
            key = self._get_password_key(password)
            ciphertext_prefixed_binary = base64.b64decode(ciphertext)
            iv = ciphertext_prefixed_binary[:self.m_ivlen]  # IV is the same as block size for CBC mode

        # Key
        key = self._encode(key)

        # Decrypt
        ciphertext_binary = ciphertext_prefixed_binary[self.m_ivlen:]
        backend = default_backend()
        cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=backend)
        decryptor = cipher.decryptor()
        padded_plaintext  = decryptor.update(ciphertext_binary) + decryptor.finalize()
        plaintext = self._pkcs7_unpad(padded_plaintext)
        return plaintext

    def _get_password_key(self, password):
        '''
        Pad the password if necessary.

        This is used by encrypt and decrypt.

        Note that the password could be hashed here instead. This
        approach is used to maintain backward compatibility.
        '''
        if len(password) >= self.m_keylen:
            key = password[:self.m_keylen]
        else:
            key = self._pkcs7_pad(password, self.m_keylen)
        return key

    def _get_key_and_iv(self, password, salt):
        '''
        Derive the key and the IV from the given password and salt.

        This is a niftier implementation than my implementation in C++
        because I modified it to support different digests.

        @param password  The password to use as the seed.
        @param salt      The salt.
        '''
        try:
            # Ignore is okay here because it will be symmetric for
            # both encrypt and decrypt operations.
            password = password.encode('utf-8', 'ignore')
            maxlen = self.m_keylen + self.m_ivlen
            keyiv = self.m_digest(password + salt).digest()
            digest = keyiv
            while len(keyiv) < maxlen:
                digest = self.m_digest(digest + password + salt).digest()
                keyiv += digest  # append the last 16 bytes
            key = keyiv[:self.m_keylen]
            iv = keyiv[self.m_keylen:self.m_keylen + self.m_ivlen]
            return key, iv
        except UnicodeDecodeError as exc:
            err('failed to generate key and iv: {}'.format(exc))
            return None, None

    def _encode(self, val):
        '''
        Encode a string for Python 2/3 compatibility.
        '''
        if isinstance(val, str):
            try:
                val = val.encode('utf-8')
            except UnicodeDecodeError:
                pass  # python 2, don't care
        return val

    def _pkcs7_pad(self, text, size):
        '''
        PKCS#7 padding.

        Pad to the boundary using a byte value that indicates
        the number of padded bytes to make it easy to unpad
        later.

        @param text  The text to pad.
        '''
        num_bytes = size - (len(text) % size)

        # Works for python3 and python2.
        if isinstance(text, str):
            text += chr(num_bytes) * num_bytes
        elif isinstance(text, bytes):
            text += bytearray([num_bytes] * num_bytes)
        else:
            assert False
        return text

    def _pkcs7_unpad(self, padded):
        '''
        PKCS#7 unpadding.

        We padded with the number of characters to unpad.
        Just get it and truncate the string.
        Works for python 2/3.
        '''
        if isinstance(padded, str):
            unpadded_len = ord(padded[-1])
        elif isinstance(padded, bytes):
            unpadded_len = padded[-1]
        else:
            assert False
        return padded[:-unpadded_len]


# ================================================================
#
# Message Utility Functions.
#
# ================================================================
def _msg(prefix, msg, level, ofp):
    '''
    Thread safe message reporting.
    '''
    th_mutex.acquire()
    try:
        ofp.write('{}:{} {}\n'.format(prefix, inspect.stack()[level][2], msg))
    finally:
        th_mutex.release()


def info(msg, level=1, ofp=sys.stdout):
    '''
    Display a simple information message with context information.
    '''
    _msg('INFO', msg, level+1, ofp)


def infov(opts, msg, level=1, ofp=sys.stdout):
    '''
    Display a simple information message with context information.
    '''
    if opts.verbose:
        _msg('INFO', msg, level+1, ofp)


def infov2(opts, msg, level=1, ofp=sys.stdout):
    '''
    Display a simple information message with context information.
    '''
    if opts.verbose > 1:
        _msg('INFO', msg, level+1, ofp)


def err(msg, level=1, ofp=sys.stdout):
    '''
    Display error message with context information and exit.
    '''
    _msg('ERROR', msg, level+1, ofp)
    abort_threads()
    sys.exit(1)


def errn(msg, level=1, ofp=sys.stdout):
    '''
    Display error message with context information but do not exit.
    '''
    _msg('ERROR', msg, level+1, ofp)


def warn(msg, level=1, ofp=sys.stdout):
    '''
    Display error message with context information but do not exit.
    '''
    _msg('WARNING', msg, level+1, ofp)


def _println(msg, ofp=sys.stdout):
    '''
    Print a message with a new line.
    '''
    th_mutex.acquire()
    try:
        ofp.write(msg + '\n')
    finally:
        th_mutex.release()


# ================================================================
#
# Thread utility functions.
#
# ================================================================
def abort_threads():
    '''
    Set the abort flag.
    '''
    th_mutex.acquire()
    try:
        global th_abort
        th_abort = True
    finally:
        th_mutex.release()


def get_num_cores():
    '''
    Get the number of available cores.
    Unforunately, multiprocessing.cpu_count() uses _NPROCESSORS_ONLN
    which may be different than the actual number of cores available
    if power saving mode is enabled.

    On Linux and Mac we can use "getconf _NPROCESSORS_CONF", I have
    no idea how to get it on windows, maybe some WMIC call.
    '''
    if os.name == 'posix':
        # should be able to run getconf.
        try:
            out = subprocess.check_output('getconf _NPROCESSORS_CONF', stderr=subprocess.STDOUT, shell=True)
            return int(out.strip())
        except subprocess.CallProcessError as exc:
            err('command failed: {}'.format(exc))

    return multiprocessing.cpu_count()


def thread_process_file(opts, password, entry, stats):
    '''
    Thread worker.

    Waits for the semaphore to make a slot available, then
    runs the specified function.
    '''
    if th_abort is False:
        with th_semaphore:
            process_file(opts, password, entry, stats)


def wait_for_threads():
    '''
    Wait for threads to complete.
    '''
    for th in threading.enumerate():
        if th == threading.currentThread():
            continue
        th.join()


# ================================================================
#
# Program specific functions.
#
# ================================================================
def get_err_fct(opts):
    '''
    Get the message function: error or warning depending on
    the --warn setting.
    '''
    if opts.warn is True:
        return warn
    return err


def stat_inc(stats, key, value=1):
    '''
    Increment the stat in a synchronous way using a mutex
    to coordinate between threads.
    '''
    th_mutex.acquire()
    try:
        stats[key] += value
    finally:  # avoid deadlock from exception
        th_mutex.release()


def check_existence(opts, path):
    '''
    Check to see if a file exists.
    If -o or --overwrite is specified, we don't care if it exists.
    '''
    if opts.overwrite is False and os.path.exists(path):
        get_err_fct(opts)('file exists, cannot continue: {}'.format(path))


def read_file(opts, path, stats):
    '''
    Read the file contents.
    '''
    try:
        with open(path, 'rb') as ifp:
            data = ifp.read()
            stat_inc(stats, 'read', len(data))
            return data
    except IOError as exc:
        get_err_fct(opts)('failed to read file "{}": {}'.format(path, exc))
        return None


def write_file(opts, path, content, stats, width=0):
    '''
    Write the file.
    '''
    try:
        with open(path, 'wb') as ofp:
            if width < 1:
                ofp.write(content)
            else:
                i = 0
                nl = '\n' if isinstance(content, str) else b'\n'
                while i < len(content):
                    ofp.write(content[i:i+width] + nl)
                    i += width
            stat_inc(stats, 'written', len(content))
    except IOError as exc:
        get_err_fct(opts)('failed to write file "{}": {}'.format(path, exc))
        return False
    return True


def lock_file(opts, password, path, stats):
    '''
    Lock a file.
    '''
    out = path + opts.suffix
    infov2(opts, 'lock "{}" --> "{}"'.format(path, out))
    check_existence(opts, out)
    content = read_file(opts, path, stats)
    if content is not None:
        data = AESCipher(openssl=opts.openssl).encrypt(password, content)
        if data is not None and write_file(opts, out, data, stats, width=opts.wll) is True and th_abort is False:
            if out != path:
                os.remove(path)  # remove the input
            stat_inc(stats, 'locked')


def unlock_file(opts, password, path, stats):
    '''
    Unlock a file.
    '''
    if path.endswith(opts.suffix):
        if len(opts.suffix) > 0:
            out = path[:-len(opts.suffix)]
        else:
            out = path
        infov2(opts, 'unlock "{}" --> "{}"'.format(path, out))
        check_existence(opts, out)
        content = read_file(opts, path, stats)
        if content is not None and th_abort is False:
            try:
                data = AESCipher(openssl=opts.openssl).decrypt(password, content)
                if write_file(opts, out, data, stats) is True:
                    if out != path:
                        os.remove(path)  # remove the input
                    stats['unlocked'] += 1
            except ValueError as exc:
                get_err_fct(opts)('unlock/decrypt operation failed for "{}": {}'.format(path, exc))
    else:
        infov2(opts, 'skip "{}"'.format(path))
        stats['skipped'] += 1


def process_file(opts, password, path, stats):
    '''
    Process a file.
    '''
    if th_abort is False:
        stat_inc(stats, 'files')
        if opts.lock is True:
            lock_file(opts, password, path, stats)
        else:
            unlock_file(opts, password, path, stats)


def process_dir(opts, password, path, stats):
    '''
    Process a directory, we always start at the top level.
    '''
    stats['dirs'] += 1
    if opts.recurse is True:
        # Recurse to get everything.
        for root, subdirs, subfiles in os.walk(path):
            for subfile in sorted(subfiles, key=str.lower):
                if subfile.startswith('.'):
                    continue
                if th_abort is True:
                    break
                subpath = os.path.join(root, subfile)
                th = Thread(target=thread_process_file, args=(opts, password, subpath, stats))
                th.daemon = True
                th.start()
    else:
        # Use listdir() to get the files in the current directory only.
        for entry in sorted(os.listdir(path), key=str.lower):
            if entry.startswith('.'):
                continue
            subpath = os.path.join(path, entry)
            if os.path.isfile(subpath):
                if th_abort is True:
                    break
                th = Thread(target=thread_process_file, args=(opts, password, subpath, stats))
                th.daemon = True
                th.start()


def process(opts, password, entry, stats):
    '''
    Process an entry.

    If it is a file, then operate on it.

    If it is a directory, recurse if --recurse was specified.
    '''
    if th_abort is False:
        if os.path.isfile(entry):
            th = Thread(target=thread_process_file, args=(opts, password, entry, stats))
            th.daemon = True
            th.start()
        elif os.path.isdir(entry):
            process_dir(opts, password, entry, stats)


def run(opts, password, stats):
    '''
    Process the entries on the command line.
    They can be either files or directories.
    '''
    for entry in opts.FILES:
        process(opts, password, entry, stats)


def summary(opts, stats):
    '''
    Print the summary statistics after all threads
    have completed.
    '''
    if opts.verbose:
        action = 'lock' if opts.lock is True else 'unlock'
        print('')
        print('Setup')
        print('   action:              {:>12}'.format(action))
        print('   inplace:             {:>12}'.format(str(opts.inplace)))
        print('   jobs:                {:>12,}'.format(opts.jobs))
        print('   overwrite:           {:>12}'.format(str(opts.overwrite)))
        print('   suffix:              {:>12}'.format('"' + opts.suffix + '"'))
        print('')
        print('Summary')
        print('   total files:         {:>12,}'.format(stats['files']))
        if opts.lock:
            print('   total locked:        {:>12,}'.format(stats['locked']))
        if opts.unlock:
            print('   total unlocked:      {:>12,}'.format(stats['unlocked']))
        print('   total skipped:       {:>12,}'.format(stats['skipped']))
        print('   total bytes read:    {:>12,}'.format(stats['read']))
        print('   total bytes written: {:>12,}'.format(stats['written']))
        print('')


def get_password(opts):
    '''
    Get the password.

    If the user specified -P or --password on the command line, use
    that.

    If the user speciried -p <file> or --password-file <file> on the
    command line, read the first line of the file that is not blank or
    starts with #.

    If neither of the above, prompt the user twice.
    '''
    # User specified it on the command line. Not safe but useful for testing
    # and for scripts.
    if opts.password:
        return opts.password

    # User specified the password in a file. It should be 0600.
    if opts.password_file:
        if not os.path.exists(opts.password_file):
            err("password file doesn't exist: {}".format(opts.password_file))
        password = None
        ifp = open(opts.password_file, 'rb')
        for line in ifp.readlines():
            line.strip()  # leading and trailing white space not allowed
            if len(line) == 0:
                continue  # skip blank lines
            if line[0] == '#':
                continue  # skip comments
            password = line
            break
        ifp.close()
        if password is None:
            err('password was not found in file ' + opts.password_file)
        return password

    # User did not specify a password, prompt twice to make sure that
    # the password is specified correctly.
    password = getpass.getpass('Password: ')
    password2 = getpass.getpass('Re-enter password: ')
    if password != password2:
        err('passwords did not match!')
    return password


def getopts():
    '''
    Get the command line options.
    '''
    def gettext(s):
        lookup = {
            'usage: ': 'USAGE:',
            'positional arguments': 'POSITIONAL ARGUMENTS',
            'optional arguments': 'OPTIONAL ARGUMENTS',
            'show this help message and exit': 'Show this help message and exit.\n ',
        }
        return lookup.get(s, s)

    argparse._ = gettext  # to capitalize help headers
    base = os.path.basename(sys.argv[0])
    name = os.path.splitext(base)[0]
    usage = '\n  {0} [OPTIONS] [<FILES_OR_DIRS>]+'.format(base)
    desc = 'DESCRIPTION:{0}'.format('\n  '.join(__doc__.split('\n')))
    epilog = r'''EXAMPLES:
   # Example 1: help
   $ {0} -h

   # Example 2: lock/unlock a single file
   $ {0} -P 'secret' file.txt
   $ ls file.txt*
   file.txt.locked
   $ {0} -P 'secret' --unlock file.txt
   $ ls -1 file.txt*
   file.txt

   # Example 3: lock/unlock a set of directories
   $ {0} -P 'secret' project1 project2
   $ find project1 project2 --type f -name '*.locked'
   <output snipped>
   $ {0} -P 'secret' --unlock project1 project2

   # Example 4: lock/unlock using a custom extension
   $ {0} -P 'secret' -s .EncRypt file.txt
   $ ls file.txt*
   file.txt.EncRypt
   $ {0} -P 'secret' -s .EncRypt --unlock file.txt

   # Example 5: lock/unlock a file in place (using the same name)
   #            The file name does not change but the content.
   #            It is compatible with the default mode of operation in
   #            previous releases.
   #            This mode of operation is not recommended because data
   #            will be lost if the disk fills up during a write.
   $ {0} -P 'secret' -i -l file.txt
   $ ls file.txt*
   file.txt
   $ {0} -P 'secret' -i -u file.txt
   $ ls file.txt*
   file.txt

   # Example 6: use a password file.
   $ echo 'secret' >pass.txt
   $ chmod 0600 pass.txt
   $ {0} -p pass.txt -l file.txt
   $ {0} -p pass.txt -u file.txt.locked

   # Example 7: encrypt and decrypt in an openssl compatible manner
   #            by specifying the compatibility (-c) option.
   $ echo 'secret' >pass.txt
   $ chmod 0600 pass.txt
   $ {0} -p pass.txt -c -l file.txt
   $ # Dump the locked password file contents, then decrypt it.
   $ openssl enc -aes-256-cbc -d -a -salt -pass file:pass.txt -in file.txt.locked
   $ {0} -p pass.txt -c -u file.txt.locked

COPYRIGHT:
   Copyright (c) 2015 Joe Linoff, all rights reserved

LICENSE:
   MIT Open Source

PROJECT:
   https://github.com/jlinoff/lock_files
 '''.format(base)
    afc = argparse.RawTextHelpFormatter
    parser = argparse.ArgumentParser(formatter_class=afc,
                                     description=desc[:-2],
                                     usage=usage,
                                     epilog=epilog)

    group1 = parser.add_mutually_exclusive_group()

    parser.add_argument('-c', '--openssl',
                        action='store_true',
                        help='''Enable openssl compatibility.
This will encrypt and decrypt in a manner
that is completely compatible openssl.

This option must be specified for both
encrypt and decrypt operations.

These two decrypt commands are equivalent.
   $ openssl enc -aes-256-cbc -d -a -salt -pass pass:PASSWORD -in FILE -o FILE.locked
   $ {0} -P PASSWORD -l FILE

These two decrypt commands are equivalent.
   $ openssl enc -aes-256-cbc -e -a -salt -pass pass:PASSWORD -in FILE.locked -o FILE
   $ {0} -P PASSWORD -u FILE
 '''.format(base))

    parser.add_argument('-d', '--decrypt',
                        action='store_true',
                        help='''Unlock/decrypt files.
This option is deprecated.
It is the same as --unlock.
 ''')

    parser.add_argument('-e', '--encrypt',
                        action='store_true',
                        help='''Lock/encrypt files.
This option is deprecated.
This is the same as --lock and is the default.
 ''')

    parser.add_argument('-i', '--inplace',
                        action='store_true',
                        help='''In place mode.
Overwrite files in place.

It is the same as specifying:
   -o -s ''

This is a dangerous because a disk full
operation can cause data to be lost when a
write fails. This allows you to duplicate the
behavior of the previous version.
 ''')

    #nc = get_num_cores()
    parser.add_argument('-j', '--jobs',
                        action='store',
                        type=int,
                        default=1,
                        metavar=('NUM_THREADS'),
                        help='''Specify the maximum number of active threads.

This can be helpful if there a lot of large
files to process where large refers to files
larger than a MB.

Default: %(default)s
 ''')

    parser.add_argument('-l', '--lock',
                        action='store_true',
                        help='''Lock files.
Files are locked and the ".locked" extension
is appended unless the --suffix option is
specified.
 ''')

    parser.add_argument('-o', '--overwrite',
                        action='store_true',
                        help='''Overwrite files that already exist.
This can be used in conjunction disable file
existence checks.

It is used by the --inplace mode.
 ''')

    group1.add_argument('-p', '--password-file',
                        action='store',
                        type=str,
                        help='''file that contains the password.
The default behavior is to prompt for the
password.
 ''')

    group1.add_argument('-P', '--password',
                        action='store',
                        type=str,
                        help='''Specify the password on the command line.
This is not secure because it is visible in
the command history.
 ''')

    parser.add_argument('-r', '--recurse',
                        action='store_true',
                        help='''Recurse into subdirectories.
 ''')

    parser.add_argument('-s', '--suffix',
                        action='store',
                        type=str,
                        default='.locked',
                        metavar=('EXTENSION'),
                        help='''Specify the extension used for locked files.
Default: %(default)s
 ''')

    parser.add_argument('-u', '--unlock',
                        action='store_true',
                        help='''Unlock files.
Files with the ".locked" extension are
unlocked.

If the --suffix option is specified, that
extension is used instead of ".locked".
 ''')

    parser.add_argument('-v', '--verbose',
                        action='count',
                        default=0,
                        help='''Increase the level of verbosity.
A single -v generates a summary report.

Two or more -v options show all of the files
being processed.
 ''')

    # Display the version number and exit.
    parser.add_argument('-V', '--version',
                        action='version',
                        version='%(prog)s version {0}'.format(VERSION),
                        help="""Show program's version number and exit.
 """)

    parser.add_argument('-w', '--wll',
                        action='store',
                        type=int,
                        default=72,
                        metavar=('INTEGER'),
                        help='''The width of each locked/encrypted line.
This is important because text files with
very, very long can sometimes cause problems
during uploads. If set to zero, no new lines
are inserted.

Default: %(default)s
''')

    parser.add_argument('-W', '--warn',
                        action='store_true',
                        help='''Warn if a single file lock/unlock fails.
Normally if the program tries to modify a
fail and that modification fails, an error is
reported and the programs stops. This option
causes that event to be treated as a warning
so the program continues.
 ''')

    # Positional arguments at the end.
    parser.add_argument('FILES',
                        nargs="*",
                        help='files to process')

    opts = parser.parse_args()

    # Make lock and unlock authoritative.
    if opts.decrypt is True:
        opts.unlock = True
    if opts.encrypt is True:
        opts.lock = True
    if opts.lock is True and opts.unlock is True:
        error('You have specified mutually exclusive options to lock/encrypt and unlock/decrypt.')
    if opts.lock is False and opts.unlock is False:
        opts.lock = True  # the default
    if opts.inplace:
        opts.suffix = ''
        opts.overwrite = True
    elif opts.overwrite == True and opts.suffix == '':
        opts.inplace = True
    return opts


def main():
    '''
    main
    '''
    opts = getopts()
    password = get_password(opts)

    stats = {
        'locked': 0,
        'unlocked': 0,
        'skipped': 0,
        'files': 0,
        'dirs': 0,
        'read': 0,
        'written': 0,
        }

    # Use the mutex for I/O to avoid interspersed output.
    # Use the semaphore to limit the number of active threads.
    global th_semaphore
    th_semaphore = Semaphore(opts.jobs)

    try:
        run(opts, password, stats)
        wait_for_threads()
    except KeyboardInterrupt:
        abort_threads()
        _println('', sys.stderr)
        errn('^C detected, cleaning up threads, please wait\n')
        wait_for_threads()

    summary(opts, stats)
    if th_abort == True:
        sys.exit(1)


if __name__ == '__main__':
    main()
