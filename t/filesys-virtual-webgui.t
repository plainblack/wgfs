use lib '/data/WebGUI/lib', '/data/wgfs/lib', '/data/experimental/wgfs/lib';
use Test::More tests=>37;
use Filesys::Virtual::WebGUI;
use WebGUI::Session;
use WebGUI::Asset;
use JSON;

my $session = WebGUI::Session->open("/data/WebGUI","dev.localhost.localdomain.conf");

# set up something to look at
my $rootAsset = WebGUI::Asset->getRoot($session);
my $andy = $rootAsset->addChild({
    className   => "WebGUI::Asset::Wobject::Folder",
    title       => "Andy",
    url         => "andy",
    });
my $red = $andy->addChild({
    className   => "WebGUI::Asset::Wobject::Folder",
    title       => "Red",
    url         => "andy/red",
    });
my $haywood = $red->addChild({
    className   => "WebGUI::Asset::Wobject::Folder",
    title       => "Haywood",
    url         => "andy/red/haywood",
    });
my $innocent = $andy->addChild({
    className   => "WebGUI::Asset::Snippet",
    title       => "Andy is Innocent",
    url         => "andy/innocent",
    snippet     => "I had to come to prison to become a crook.",
    });
my $guilty = $red->addChild({
    className   => "WebGUI::Asset::Snippet",
    title       => "Red is 'innocent'",
    url         => "andy/red/innocent",
    snippet     => "Everybody in here is innocent.",
    });

# basics
my $fs = Filesys::Virtual::WebGUI->new({session=>$session, root=>'/andy'});
isa_ok($fs, 'Filesys::Virtual::WebGUI');
ok(!$fs->login('xx','yy'), "invalid credentials");
ok($fs->login('admin','123qwe'), 'valid credentials');

# lists 
my @assets = $fs->list('/bad');
ok(!scalar(@assets), 'list() nothing to see');
@assets = $fs->list('/andy/red');
is(scalar(@assets), 2, "2 things in reds folder");
is($assets[1], "innocent", "second things in reds folder is innocent");
@assets = $fs->list_details('/bad');
ok(!scalar(@assets), 'list_details() nothing to see');
@assets = $fs->list_details('/andy');
is(scalar(@assets), 2, "2 things in andys folder");
like($assets[1], qr/innocent$/, "second things in andys folder is innocent");

# change directories
is($fs->cwd, "/andy", "cwd == root");
ok(!$fs->chdir("/bad"), "can't change to a bad place");
ok($fs->chdir("/andy/red"), "can change to a good place");
is($fs->cwd, "/andy/red", "we really changed");

# reads
my $fh = $fs->open_read("/andy/red/innocent");
isa_ok($fh, 'IO::Scalar');
is(JSON->new->decode($fh->getlines)->{title}, "Red is 'innocent'", "Can read a snippet.");
ok($fs->close_read($fh), "Close a snippet.");
is($fs->size('/andy'), $andy->get('assetSize'), "size()");
is($fs->modtime('/andy'), $session->datetime->epochToHuman($andy->getContentLastModified, '%y%m%d%h%n%s'), "modtime()");

# writes
$fh = $fs->open_write("/andy/rita.jpg");
isa_ok($fh, 'IO::File');
my $image = IO::File->new('/data/WebGUI/t/supporting_collateral/gooey.jpg');
while (my $line = <$image>) {
    $fh->print($line);
}
ok($fs->close_write($fh), 'close an image');
$image->close;
my $rita = WebGUI::Asset->newByUrl($session, '/andy/rita.jpg');
isa_ok($rita, 'WebGUI::Asset::File::Image', 'rita is an image');
is($rita->get('filename'), 'rita.jpg', 'file is named appropriately');
my $store = $rita->getStorageLocation;
ok(-e $store->getPath($rita->get('filename')), 'file was created');
cmp_ok($rita->get('assetSize'), '>', 20000, 'file seems large enough');
$fh = $fs->open_write('/andy/red/haywood/innocent.txt');
isa_ok($fh,'IO::Scalar');
$fh->print(JSON->new->encode({
    title       => "Haywood is 'innocent'",
    snippet     => "I'm innocent. Lawyer fucked me.",
}));
ok($fs->close_write($fh), "close a new snippet");
my $lawyer = WebGUI::Asset->newByUrl($session, '/andy/red/haywood/innocent.txt');
isa_ok($lawyer, 'WebGUI::Asset::Snippet', "created correct asset type");
is($lawyer->get('snippet'), "I'm innocent. Lawyer fucked me.", "get snippet contents");
ok(!$fs->chmod(), "chmod doesn't work");
ok($fs->mkdir('floyd'), 'mkdir()');
my $floyd = WebGUI::Asset->newByUrl($session, '/andy/red/floyd');
isa_ok($floyd, 'WebGUI::Asset::Wobject::Folder', 'mkdir() is a folder');
is($floyd->get('title'), 'floyd', "mkdir() makes a good title");
is($fs->utime(0,0, qw(/andy/red /andy/innocent)), 2, "utime()");

# test() tests

# deletes
ok($fs->delete('/andy/red/haywood/innocent.txt'), 'delete() success');
my $innocenceLost = WebGUI::Asset->newByUrl($session, '/andy/red/haywood/innocent.txt');
is($innocenceLost->get('state'), 'trash', "asset in trash after delete");
ok(!$fs->delete('/andy/red/brooks'), 'delete() fail');
ok($fs->rmdir('/andy/red/haywood'), 'delete() success');




END {
    $andy->purge;
}


