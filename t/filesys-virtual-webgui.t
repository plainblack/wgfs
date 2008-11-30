use lib '/data/WebGUI/lib', '/data/wgfs/lib', '/data/experimental/wgfs/lib';
use Test::More tests=>81;
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
my $fs = Filesys::Virtual::WebGUI->new({session=>$session, root_path=>'/andy'});
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
my @stat = $fs->stat("/andy");
is(scalar(@stat), 13, "stat()");
is($stat[2], 16877, "stat() produces a good mode");


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
$haywood->update({ownerUserId=>'1',groupIdView=>'1',groupIdEdit=>'3'});
$floyd->update({ownerUserId=>'3',groupIdView=>'3',groupIdEdit=>'3'});
$session->user({userId=>1});
ok($fs->test('r', '/andy'), '-r test success');
ok(!$fs->test('r', '/andy/red/floyd'), '-r test fail');
ok($fs->test('w', '/andy/red/haywood'), '-w test success');
ok(!$fs->test('w', '/andy/red/floyd'), '-w test fail');
ok($fs->test('x', '/andy'), '-x test success');
ok(!$fs->test('x', '/andy/red/floyd'), '-x test fail');
ok($fs->test('o', '/andy/red/haywood'), '-o test success');
ok(!$fs->test('o', '/andy/red'), '-o test fail');
ok($fs->test('R', '/andy'), '-R test success');
ok(!$fs->test('R', '/andy/red/floyd'), '-R test fail');
ok($fs->test('W', '/andy/red/haywood'), '-W test success');
ok(!$fs->test('W', '/andy/red/floyd'), '-W test fail');
ok($fs->test('X', '/andy'), '-X test success');
ok(!$fs->test('X', '/andy/red/floyd'), '-X test fail');
ok($fs->test('O', '/andy/red/haywood'), '-O test success');
ok(!$fs->test('O', '/andy/red'), '-O test fail');
ok($fs->test('e', '/andy'), '-e test success');
ok(!$fs->test('e', '/andy/fresh-fish'), '-e test fail');
cmp_ok($fs->test('z', '/andy'), '>', 0, '-z test success');
is($fs->test('z', '/andy/fresh-fish'), 0, '-z test fail');
cmp_ok($fs->test('s', '/andy'), '>', 0, '-s test success');
is($fs->test('s', '/andy/fresh-fish'), 0, '-s test fail');
ok($fs->test('f', '/andy/innocent'), '-f test success');
ok(!$fs->test('f', '/andy'), '-f test fail');
ok($fs->test('d', '/andy'), '-d test success');
ok(!$fs->test('d', '/andy/innocent'), '-d test fail');
ok(!$fs->test('l', '/andy'), '-l test fail');
ok(!$fs->test('p', '/andy'), '-p test fail');
ok(!$fs->test('S', '/andy'), '-S test fail');
ok(!$fs->test('b', '/andy'), '-b test fail');
ok(!$fs->test('c', '/andy'), '-c test fail');
ok(!$fs->test('t', '/andy'), '-t test fail');
ok(!$fs->test('u', '/andy'), '-u test fail');
ok(!$fs->test('g', '/andy'), '-g test fail');
ok(!$fs->test('k', '/andy'), '-k test fail');
ok($fs->test('T', '/andy/innocent'), '-T test success');
ok(!$fs->test('T', '/andy/rita.jpg'), '-T test fail');
ok($fs->test('B', '/andy/rita.jpg'), '-B test success');
ok(!$fs->test('B', '/andy/innocent'), '-B test fail');
sleep(1); # wait so we have something to count for these next 3 tests
my $age = $fs->test('M','/andy');
ok($age > 0 && $age < 1, '-M test success');
$age = $fs->test('A','/andy');
ok($age > 0 && $age < 1, '-A test success');
$age = $fs->test('C','/andy');
ok($age > 0 && $age < 1, '-C test success');
$session->user({userId=>3});


# deletes
ok($fs->delete('/andy/red/haywood/innocent.txt'), 'delete() success');
my $innocenceLost = WebGUI::Asset->newByUrl($session, '/andy/red/haywood/innocent.txt');
is($innocenceLost->get('state'), 'trash', "asset in trash after delete");
ok(!$fs->delete('/andy/red/brooks'), 'delete() fail');
ok($fs->rmdir('/andy/red/haywood'), 'delete() success');




END {
    $andy->purge;
    $session->close;
}


