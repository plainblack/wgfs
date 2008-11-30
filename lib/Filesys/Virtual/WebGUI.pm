package Filesys::Virtual::WebGUI;

use strict;
use base 'Filesys::Virtual';
use JSON;
use IO::File;
use IO::Scalar;
use WebGUI::Session;
use WebGUI::User;
use WebGUI::Asset;
use WebGUI::VersionTag;
use WebGUI::Utility qw(isIn);
use WebGUI::User;
use WebGUI::Group;

# login: exactly that

sub login {
    my ($self, $username, $password) = @_;
    my $session = $self->session;
    my $log = $session->log; 
    $log->info("Authenticating $username for VFS");
    my $user = WebGUI::User->newByUsername($session, $username);
    if (defined $user) {
        my $authMethod = $user->authMethod;
        if ($authMethod) { # we have an auth method, let's try to instantiate
            my $auth = eval { WebGUI::Pluggable::instanciate("WebGUI::Auth::".$authMethod, "new", [ $session, $authMethod ] ) };
            if ($@) { # got an error
                $log->error($@);
                return 0;
            }
            elsif ($auth->authenticate($username, $password)) { # lets try to authenticate
                $log->info("Authenticated $username successfully for VFS");
                my $sessionId = $session->db->quickScalar("select sessionId from userSession where userId=?",[$user->userId]);
                unless (defined $sessionId) { # no existing session found
                    $log->info("VFS: creating new session");
                    $sessionId = $session->id->generate;
                    $auth->_logLogin($user->userId, "success (VFS)");
                }
                $session->{_var} = WebGUI::Session::Var->new($session, $sessionId);
                $session->user({user=>$user});
                return 1;
            }
        }
    }
    $log->security($username." failed to login for VFS");
    return 0;
}

# size: get a file's size

sub size {
    my ($self, $path) = @_;
    my $asset = $self->resolvePath($path, 1);
    if (defined $asset && $asset->canView) {
        return $asset->get('assetSize');
    }
    return 0;
}

# chmod: Change a file's mode

sub chmod {
    my ($self, $mode, $fn) = @_;
    return 0;    
}

# modtime: Return the modification time for a given file

sub modtime {
    my ($self, $path) = @_;
    my $asset = $self->resolvePath($path, 1);
    if (defined $asset && $asset->canView) {
        return $self->session->datetime->epochToHuman($asset->getContentLastModified, '%y%m%d%h%n%s');
    }
    return "00000000000000";
}

# delete: Delete a given file

sub delete {
    my ($self, $path) = @_;
    my $asset = $self->resolvePath($path, 1);
    if (defined $asset && $asset->canEdit) {
        $asset->trash;
        return 1;
    }
    return 0;
}

# cwd:

sub cwd {
    my ($self, $newDir) = @_;
    $self->chdir($newDir) if (defined $newDir);
    return $self->{_cwd};
}

# chdir: Change the cwd to a new path

sub chdir {
    my ($self, $newDir) = @_;
    $newDir = $self->resolvePath($newDir);
    if (defined $newDir) {
        my $asset = $self->resolvePath($newDir, 1);
        if (defined $asset && $asset->canView) { 
            $self->{_cwd} = $newDir;
            return 1;
        }
    }
    return 0;
}

# mkdir: Create a new directory

sub mkdir {
    my ($self, $path) = @_;
    $path = $self->resolvePath($path);
    my $basePath = $path;
    $basePath =~ s{(.*)\/.*$}{$1}xms; # remove the last node
    my $base = $self->resolvePath($basePath, 1);
    if (defined $base && $base->canEdit) {
        my $folder = $path;
        $folder =~ s{.*\/(.*)$}{$1}xms; # get filename
        my $asset = $base->addChild({
            title       => $folder,
            menuTitle   => $folder,
            url         => $path,
            className   => 'WebGUI::Asset::Wobject::Folder',
        });
        WebGUI::VersionTag->getWorking($self->session)->commit;
        return defined $asset;
    }
    return 0;
}

# rmdir: Remove a directory or file

sub rmdir {
    my ($self, $path) = @_;
    return $self->delete($path);
}

# list: List files in a path.

sub list {
    my ($self, $path) = @_;
    my $base = $self->resolvePath($path, 1);
    my @assets;
    if (defined $base && $base->canView) {
        my $nextAsset = $base->getLineageIterator(["children"], {returnObjects=>1});
        while (my $asset = $nextAsset->()) {
            next unless $asset->canView;
            my $filename = $asset->get('url');
            $filename =~ s{.*\/(.*?)$}{$1}xms; 
            push @assets, $filename; 
        }
    }
    return @assets;
}

# list_details: List files in a path, in full ls -al format.

sub list_details {
    my ($self, $path) = @_;
    my $base = $self->resolvePath($path, 1);
    my @assets;
    if (defined $base && $base->canView) {
        my $nextAsset = $base->getLineageIterator(["children"], {returnObjects=>1});
        while (my $asset = $nextAsset->()) {
            next unless $asset->canView;

            # determine type
            my $type = ($asset->isa('WebGUI::Asset::Wobject::Folder')) ? 'd' : '-';

            # determine mode
            my $mode = "rwx";
            if ($asset->get('groupIdEdit') eq $asset->get('groupIdView')) {
                $mode .= "rwx";
            }
            else {
                $mode .= "r-x";
            }
            if ($asset->get('groupIdEdit') eq '7') {
                $mode .= "rwx";
            }
            elsif ($asset->get('groupIdView') eq '7') {
                $mode .= "r-x";
            }
            else {
                $mode .= "---";
            }

            # determine filename
            my $filename = $asset->get('url');
            $filename =~ s{.*\/(.*?)$}{$1}xms; 

            # determine time
            my ($dow, $month, $day, $time, $year) = (localtime($asset->getContentLastModified) =~ m/(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/);
            if ((localtime())[5]+1900 eq $year) {
                $year = substr($time, 0, 5);
            }

            # determine username
            my $user = WebGUI::User->new($self->session, $asset->get('ownerUserId'));
            my $username = $user->username if (defined $user);

            # determine groupname
            my $group = WebGUI::Group->new($self->session, $asset->get('groupIdView'));
            my $groupname = $group->name if (defined $group);

            # add it to the list
            push @assets, sprintf("%1s%9s %4s %-8s %-8s %8s %3s %2s %5s %s",
                                $type,
                                $mode,
                                1, # number of hard links
                                $username,
                                $groupname,
                                $asset->get('assetSize'),
                                $month,
                                $day,
                                $year,
                                $filename
                                ); 
        }
    }
    return @assets;
}

# new: pass in a session

sub new {
    my ($class, $options) = @_;
    my $session = $options->{session};
    my $root = $options->{root};
    bless {_session => $session, _root=>$root, _cwd=>$root}, $class;
}

# figure out the path

sub resolvePath {
    my ($self, $requested, $returnAsset) = @_;
    
    ## sanitize
    # remove a trailing /
    $requested =~ s{(.*)\/$}{$1}xms; 

    ## figure out path
    my $actual;
    # starts with a / so it's a real path
    if ($requested =~ m{^\/}) {
        $actual = $requested;
    }
    # wants parent of cwd
    elsif ($requested eq '..') {
        $actual = $self->cwd;
        $actual =~ s{(.*)\/.*$}{$1}xms; # remove the last node
    }
    # something there, so it's relative to the cwd
    elsif (defined $requested) {
        $actual = $self->cwd.'/'.$requested;
    }
    # nothing specified, so lets use cwd
    else {
        $actual = $self->cwd;
    }
    # is the new folder inside the root?
    my $root = $self->{_root};
    if ($actual !~ m{^$root}) {
        $actual = undef;
    }

    ## what to return
    # return an asset
    if ($returnAsset && defined $actual) {
        # lets see if we can save some time
        if ($self->{_lastAssetUrl} eq $actual) { 
            return $self->{_lastAsset};
        }
        $self->{_lastAsset} = WebGUI::Asset->newByUrl($self->session, $actual);
        $self->{_lastAsstUrl} = $actual;
        return $self->{_lastAsset};
    }
    # return the full path
    return $actual;
}

# session: retrieves the current session

sub session {
    my $self = shift;
    return $self->{_session};
}

# stat: Perform a stat on a given file

sub stat {
    my ($self, $fn) = @_;
    
    die ref($self)."::stat() Unimplemented";
    
    return undef;
}

# test: Perform a given filesystem test

#    -r  File is readable by effective uid/gid.
#    -w  File is writable by effective uid/gid.
#    -x  File is executable by effective uid/gid.
#    -o  File is owned by effective uid.

#    -R  File is readable by real uid/gid.
#    -W  File is writable by real uid/gid.
#    -X  File is executable by real uid/gid.
#    -O  File is owned by real uid.

#    -e  File exists.
#    -z  File has zero size.
#    -s  File has nonzero size (returns size).

#    -f  File is a plain file.
#    -d  File is a directory.
#    -l  File is a symbolic link.
#    -p  File is a named pipe (FIFO), or Filehandle is a pipe.
#    -S  File is a socket.
#    -b  File is a block special file.
#    -c  File is a character special file.
#    -t  Filehandle is opened to a tty.

#    -u  File has setuid bit set.
#    -g  File has setgid bit set.
#    -k  File has sticky bit set.

#    -T  File is a text file.
#    -B  File is a binary file (opposite of -T).

#    -M  Age of file in days when script started.
#    -A  Same for access time.
#    -C  Same for inode change time.

sub test {
    my ($self, $test, $fn) = @_;
    my $asset = $self->resolvePath($fn);
    return 0 unless defined $asset; # -e
    return 0 unless $asset->canView;
    if (isIn($test, qw(-s -z))) {
        return $asset->get('assetSize');
    } 
    elsif (isIn($test, qw(-r -x -R -X))) {
        return $asset->canView;
    } 
    elsif (isIn($test, qw(-w -W))) {
        return $asset->canEdit;
    } 
    elsif (isIn($test, qw(-o -O))) {
        return $asset->get('ownerUserId') eq $self->session->user->userId;
    } 
    elsif ($test eq '-f') {
        return !$asset->isa('WebGUI::Asset::Wobject::Folder');
    } 
    elsif ($test eq '-d') {
        return $asset->isa('WebGUI::Asset::Wobject::Folder');
    } 
    elsif ($test eq '-B') {
        return $asset->isa('WebGUI::Asset::File');
    } 
    elsif ($test eq '-T') {
        return $asset->isa('WebGUI::Asset::Snippet');
    } 
    elsif (isIn($test, qw(-M -A -C))) {
        return $asset->getContentLastModified / 60 * 60 * 24;
    } 
    return 0; # -l -p -S -b -c -t -u -g -k
}

# open_read

sub open_read {
    my ($self, $path, @opts) = @_;
    my $asset = $self->resolvePath($path, 1);
    if (defined $asset && $asset->canView) {
        if ($asset->isa('WebGUI::Asset::File')) {
            my $pathtofile = $asset->getStorageLocation->getPath($asset->get('filename'));
            return IO::File->new($pathtofile,@opts);
        }
        else {
            my $json = JSON->new->encode($asset->get);
            return IO::Scalar->new(\$json);
        }
    }
    return undef;
}

# close_read

sub close_read {
    my ($self, $fh) = @_;
    return $fh->close;
}

# open_write

sub open_write {
    my ($self, $path, $append) = @_;
    my $asset = $self->resolvePath($path, 1);
    # update an existing asset
    if (defined $asset) {
        if ($asset->canEdit) {
            if ($asset->isa('WebGUI::Asset::File')) {
                my $pathtofile = $asset->getStorageLocation->getPath($asset->get('filename'));
                my $o = (defined($append)) ? '>>' : '>';
                $asset->addRevision({});
                my $fh = IO::File->new($o.$pathtofile);
                $fh->binmode;
                $self->{_openFiles}{$fh->fileno} = $asset;
                return $fh;
            }
            else {
                $asset->addRevision;
                $self->{_openScalars}{$path} = $asset;
                my $fh = IO::Scalar->new;
                $fh->print($path."\n");
                return $fh;
            }
        }
    }
    # create a new asset
    else {
        my $parentPath = $self->resolvePath($path);
        $parentPath =~ s{(.*)\/.*$}{$1}xms; # remove the last node        
        my $parent = $self->resolvePath($parentPath,1);
        if (defined $parent && $parent->canEdit) {
            my $filename = lc($path);
            $filename =~ s{.*\/(.*?)$}{$1}xms; 
            my $extension = $filename;
            $extension =~ s{.*\.(.*?)$}{$1}xms;
            if ($extension =~ m/(jpg|png|gif)/i) {
                my $asset = $parent->addChild({
                    title       => $filename,
                    menuTitle   => $filename,
                    filename    => $filename,
                    url         => $path,
                    className   => 'WebGUI::Asset::File::Image',
                });
                my $fh = IO::File->new('>'.$asset->getStorageLocation->getPath($filename));
                $fh->binmode;
                $self->{_openFiles}{$fh->fileno} = $asset;
                return $fh;
            }
            elsif ($extension =~ m/(tmpl|template)/i) {
                my $asset = $parent->addChild({
                    title       => $filename,
                    menuTitle   => $filename,
                    url         => $path,
                    className   => 'WebGUI::Asset::Template',
                });
                $self->{_openScalars}{$path} = $asset;
                my $fh = IO::Scalar->new;
                $fh->print($path."\n");
                return $fh;
            }
            elsif ($extension =~ m/(css|html|xml|json|xhtml|txt)/i) {
                my $type = 'text/plain';
                if ($extension eq 'css') {
                    $type = 'text/css';
                }
                elsif ($extension eq 'xml' || $extension eq 'xhtml') {
                    $type = 'text/xml';
                }
                elsif ($extension eq 'html') {
                    $type = 'text/html';
                }
                elsif ($extension eq 'json') {
                    $type = 'application/json';
                }
                my $asset = $parent->addChild({
                    title       => $filename,
                    menuTitle   => $filename,
                    url         => $path,
                    mimeType    => $type,
                    className   => 'WebGUI::Asset::Snippet',
                });
                $self->{_openScalars}{$path} = $asset;
                my $fh = IO::Scalar->new;
                $fh->print($path."\n");
                return $fh;
            }
            else {
                my $asset = $parent->addChild({
                    title       => $filename,
                    menuTitle   => $filename,
                    url         => $path,
                    filename    => $filename,
                    className   => 'WebGUI::Asset::File',
                });
                my $fh = IO::File->new('>'.$asset->getStorageLocation->getPath($filename));
                $fh->binmode;
                $self->{_openFiles}{$fh->fileno} = $asset;
                return $fh;
            }
        }
    }
    return undef;
}

# close_write

sub close_write {
    my ($self, $fh) = @_;
    if ($fh->isa('IO::Scalar')) {
        seek($fh, 0, 0);
        my $path = $fh->getline;
        chomp $path;
        my $json = join('',$fh->getlines);
        my $asset = $self->{_openScalars}{$path};
        delete $self->{_openScalars}{$path};
        $asset->update(JSON->new->decode($json));
    }
    elsif ($fh->isa('IO::File')) {
        my $asset = $self->{_openFiles}{$fh->fileno};  
        delete $self->{_openFiles}{$fh->fileno};
        $asset->setSize;
    }
    WebGUI::VersionTag->getWorking($self->session)->commit;
    return $fh->close;
}

# seek: seek, if supported by filesystem...
# ie $fh is a filehandle
# $fh->seek($first, $second);
# see the module Filehandle

sub seek {
    my ($self, $fh, $first, $second) = @_;
    return seek($fh, $first, $second);
}

# utime: modify access time and mod time

sub utime {
    my ($self, $atime, $mtime, @fn) = @_;
    my $counter = 0;
    foreach my $path (@fn) {
        my $asset = $self->resolvePath($path, 1);
        if (defined $asset && $asset->canView) {
            $asset->update(); # updates last modified time
            $counter++;
        }
    }
    return $counter;
}

1;

