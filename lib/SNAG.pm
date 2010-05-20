package SNAG;
use Moose;
use File::Basename;
use Sys::Hostname;
use Getopt::Long;
use FileHandle;
use POE;
use Date::Format;
use Mail::Sendmail;
use File::Spec::Functions qw/rootdir catpath catfile devnull catdir/;
use Config::General qw/ParseConfig/;

our %flags;
our $VERSION = '4.22';

with 'SNAG::daemon', 'SNAG::logger';

# OS info
has OS => (is => 'rw', 'isa' => 'Str', default => '__OS__' );
has OSDIST => (is => 'rw', 'isa' => 'Str', default => '__OSDIST__');
has OSVER => (is => 'rw', 'isa' => 'Str', default => '__OSVER__');
has OSLONG => (is => 'rw', 'isa' => 'Str', default => '__OSLONG__');
has config_path => (is => 'rw', isa => 'ArrayRef[Str]', 
										default => sub {[ '/etc/', '.', '/opt/snag']} );

# constants
has REC_SEP => (is => 'ro', isa => 'Str', default => '~_~');
has RRD_SEP => (is => 'ro', isa => 'Str', default => ':');
has LINE_SEP => (is => 'ro', isa => 'Str', default => '_@%_');
has PARCEL_SEP => (is => 'ro', isa => 'Str', default => '@%~%@');
has INFO_SEP => (is => 'ro', isa => 'Str', default => ':%:');

# config
has SMTP => (is => 'rw', isa => 'Str', default => '__SMTP__');
has SENDTO => (is => 'rw', isa => 'Str', default => '__SENDTO__');
has BASE_DIR => (is => 'rw', isa => 'Str', default => '__BASE_DIR__');
has LOG_DIR => (is => 'rw', isa => 'Str', default => '__LOG_DIR__');
has STATE_DIR => (is => 'rw', isa => 'Str', default => '__STATE_DIR__');
has CFG_DIR => (is => 'rw', isa => 'Str', default => '__CFG_DIR__');
has TMP_DIR => (is => 'rw', isa => 'Str', default => '__TMP_DIR__');
has CONF => (is => 'rw', isa => 'HashRef', default => sub { {conf => 'test'} });

has HOSTNAME => (is => 'rw', isa => 'Str', default => '__HOSTNAME__');
has SCRIPT_NAME => (is => 'ro', isa => 'Str', default => sub{ basename $0; });

has DNS => (is => 'rw', isa => 'HashRef', default => sub { {} });


sub BUILD {
  my $self = shift;
  $self->_build_os();
	$self->_parse_config();
  $self->_hostname();

	return $self;
}


sub _parse_config {
	my $self = shift;

	my $conf;
	eval {
		%$conf = ParseConfig(-ConfigFile => "snag.conf", -ConfigPath => $self->config_path);
	};
	if($@) { # and debug?
		# change to cluck/croak?
		print "snag.conf not found!  This will result in many constants not working properly.";
	}

	$self->SMTP($conf->{message}->{smtp}) if $conf->{message}->{smtp};
	$self->SENDTO($conf->{message}->{email}) if $conf->{message}->{email};
	$self->BASE_DIR($conf->{directory}->{base_dir}) if $conf->{directory}->{base_dir};
	$self->LOG_DIR($conf->{directory}->{log_dir}) if $conf->{directory}->{log_dir};
	$self->STATE_DIR($conf->{directory}->{state_dir}) if $conf->{directory}->{state_dir};
	$self->CFG_DIR($conf->{directory}->{conf_dir}) if $conf->{directory}->{conf_dir};
	$self->TMP_DIR($conf->{directory}->{tmp_dir}) if $conf->{directory}->{tmp_dir};
	$self->CONF($conf);
}

sub _build_os {
	my ($self) = shift;
  
	my($os,$dist,$ver,$long);
	if($^O =~ /linux/i)
	{
		$os = "Linux";

		my $release;
		if(-e '/etc/redhat-release')
		{
			{
				local $/;

				open FILE, "/etc/redhat-release";
				$release = <FILE>;
				close FILE;
			}

			$long = $release;
			chomp $long;

			###Red Hat Enterprise Linux AS release 3 (Taroon Update 5)
			###Red Hat Enterprise Linux AS release 4 (Nahant Update 1)
			###Red Hat Enterprise Linux WS release 3 (Taroon Update 5)
			if($release =~ /Red Hat Enterprise Linux \w+ release ([\.\d]+)/)
			{
				($ver = $1) =~ s/\.//g;
				$dist = 'RHEL';
			}
			###Red Hat Linux release 7.2 (Enigma)
			elsif($release =~  /Red Hat Linux release ([\d\.]+)/)
			{
				($ver = $1) =~ s/\.//g;
				$dist = 'RH';
			}
			#Fedora Core release 4 (Stentz)
			elsif($release =~ /Fedora Core release (\d+)/)
			{
				$ver = $1;
				$dist = 'FC';
			}
			elsif($release =~ /Cisco Clean Access /)
			{
				$dist = 'CCA';
			}
			#XenServer release 3.2.0-2004d (xenenterprise)
			elsif($release  =~ /XenServer release (\d+)/)
			{
				#$ver = $1;
				$dist = 'XenSource';
			}
		}
		elsif(-e '/etc/gentoo-release')
		{
			{
				local $/;

				open FILE, "/etc/gentoo-release";
				$release = <FILE>;
				close FILE;
			}

			$long = $release;
			chomp $long;

			#Gentoo Base System version 1.6.13
			#Gentoo Base System release 1.12.9
			if($release =~ /Gentoo Base System (version|release) ([\.\d]+)/)
			{
				($ver = $2) =~ s/\.//g;
				$dist = "GENTOO";
			}    
		}
		elsif(-e '/etc/cp-release')
		{
			{
				local $/;

				open FILE, "/etc/cp-release";
				$release = <FILE>;
				close FILE;
			}

			$long = $release;
			chomp $long;

			#Check Point SecurePlatform NGX (R62)
			if($release =~ /Check Point SecurePlatform NGX \((\w+)\)/)
			{
				($ver = $1) =~ s/\.//g;
				$dist = "CP";
			}
		}
		elsif(-e '/proc/vmware/version')
		{
			$long = `vmware -v`;
			chomp $long;
			if($long =~ /VMware ESX Server (.+?)/)
			{
				$dist = 'VMwareESX';
				#$ver = $1;
			}
		}
	}
	elsif($^O =~ /solaris/i || $^O =~ /SunOS/i)
	{
		$os = $dist = "SunOS";

		my $release = `uname -a`;
		chomp $release;

		#SunOS dhcp2 5.8 Generic_108528-15 sun4u sparc SUNW,UltraAX-i2
		if($release =~ /SunOS [\w\.\-]+ ([\d\.]+)/)
		{
			$long = "SunOS $1";
			($ver = $1) =~ s/\.//g;
		}
	}
	elsif($^O =~ /MSWin32/i)
	{
		$os = "Windows";

		my $get_dist =
		{
			'4' =>
			{
				'0' => 'NT4',
			},
			'5' =>
			{
				'0' => '2K',
				'1' => 'XP',
				'2' => 'Server2003',
			},
			'6' =>
			{
				'0' => 'Vista',
			},
		};

		require Win32;

		my ($string, $major, $minor, $build, $id) = Win32::GetOSVersion();
		$dist = $get_dist->{ $major }->{ $minor } || $os;

		#$ver = $build;
	}
	else
	{
		$os = $^O;
	}

  $self->OS($os) if $os;
	$self->OSDIST($dist) if $dist;
	$self->OSVER($ver) if $ver;
	$self->OSLONG($long) if $long;
}

sub _hostname 
{
	my $self = shift;
	my $host;
  if($self->OS eq 'Windows')
  {
    require Win32::OLE;
    import Win32::OLE qw/in/;
  
    my $wmi = Win32::OLE->GetObject("winMgmts:{(Security)}!//");
  
    my $get_computer_system = $wmi->ExecQuery('select * from Win32_ComputerSystem');
    foreach my $ref ( in $get_computer_system )
    {
      $host = $ref->{Name} . '.' . $ref->{Domain};
    }
  }
  else
  {
    eval
    {
      require Sys::Hostname::FQDN;
      import  Sys::Hostname::FQDN qw(fqdn);
      $host = fqdn() or die "Fatal: Could not get host name!";
    };
    if($@)
    {
      #print "Sys::Hostname::FQDN not found, defaulting to Sys::Hostname\n";
      $host = hostname or die "Fatal: Could not get host name!";
    }
  }
  if(defined $self->CONF->{network}->{domain})
  {
    $host =~ s/\.$self->CONF->{network}->{domain}//gi;
  }
  $host = lc($host);

  $self->HOSTNAME($host);
}

sub dns
{
	my ($self, $arg) = @_;
  require Net::Nslookup;

  ### Only run this session of the dns sub is used
  ###  This session should only be created once; since it sets $dns to an empty hash it will pass the following test every time after the first time
  unless(ref $self->DNS)
  {
    POE::Session->create
    (
      inline_states =>
      {
        _start => sub
        {
          my ($kernel, $heap) = @_[KERNEL, HEAP];
          $kernel->yield('clear');
        },

        clear => sub
        {
          my ($kernel, $heap) = @_[KERNEL, HEAP];
          ## Clear $dns every 6 hours

          $self->DNS({});

          $kernel->delay('clear' => 21600);
        },
      }
    );
  }

  if($arg =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)
  {
    ### It's an IP, return a hostname
    return $self->DNS->{ip}->{$arg} ||= (Net::Nslookup::nslookup(host => $arg, type => 'PTR') || $arg);
  }
  else
  {
    ### It's a hostname, return an IP
    return $self->DNS->{hostname}->{$arg} ||= (Net::Nslookup::nslookup(host => $arg, type => 'A') || $arg);
  }
}


1
