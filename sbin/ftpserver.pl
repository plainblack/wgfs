use lib '/data/WebGUI/lib', '/data/wgfs/lib', '/data/experimental/wgfs/lib';
use POE qw(Component::Server::FTP);
use Filesys::Virtual::WebGUI;
use WebGUI::Session;

my $session = WebGUI::Session->open("/data/WebGUI", "dev.localhost.localdomain.conf");

POE::Component::Server::FTP->spawn(
    Alias           => 'ftpd',                      # ftpd is default
    ListenPort      => 2112,                        # port to listen on
    Domain          => 'plainblack.com',            # domain shown on connection
    Version         => 'ftpd v1.0',                 # shown on connection, you can mimic...
    AnonymousLogin  => 'allow',                      # deny, allow
    FilesystemClass => 'Filesys::Virtual::WebGUI',  # Currently the only one available
    FilesystemArgs  => {
        {
        'session'   => $session,                    # a reference to the webgui session
        'root'      => '/files',                    # This is actual root for all paths
        }
    },
    # use 0 to disable these Limits
    DownloadLimit   => (50 * 1024),                 # 50 kb/s per ip/connection (use LimitScheme to configure)
    UploadLimit     => (100 * 1024),                # 100 kb/s per ip/connection (use LimitScheme to configure)
    LimitScheme     => 'ip',                        # ip or per (connection)

    LogLevel        => 4,                           # 4=debug, 3=less info, 2=quiet, 1=really quiet
    TimeOut         => 120,                         # Connection Timeout
);

$poe_kernel->run();

$session->close;
