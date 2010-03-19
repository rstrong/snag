package SNAG::Source::SystemStats::Linux;

use SNAG;
use POE;
use POE::Wheel::Run;
use POE::Filter::Line;
use Time::Local;
use URI::Escape;
use Data::Dumper;
use strict;

my $host = HOST_NAME;
my $rrd_step   = $SNAG::Source::SystemStats::rrd_step;
my $rrd_min    = $rrd_step/60;
our $stat_quanta = $rrd_step - 2;
our $stat_loops  = $rrd_min + 1;

#####################################################################################
############  DF  ############################################################
#####################################################################################

sub run_df
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{df_wheel} = POE::Wheel::Run->new
  (
    Program      => sub
                    {
                      foreach my $dev (keys %{$SNAG::Dispatch::shared_data->{mounts}})
                      {
                        next if $SNAG::Dispatch::shared_data->{mounts}->{$dev}->{type} =~ m/nfs/i;
                        my $mount = $SNAG::Dispatch::shared_data->{mounts}->{$dev}->{mount};
                        my @df_output = `/bin/df -kP $mount`;

                        shift @df_output;

                        foreach my $df_line (@df_output)
                        {
                          print "$df_line";
                        }
                      }
                    },
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_df_child_stdio',
    StderrEvent  => 'supp_df_child_stderr',
    CloseEvent   => "supp_df_child_close",
  );
}

sub run_df_nfs
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{df_nfs_wheel} = POE::Wheel::Run->new
  (
    Program      => sub
                    {
                      foreach my $dev (keys %{$SNAG::Dispatch::shared_data->{mounts}})
                      {
                        next unless $SNAG::Dispatch::shared_data->{mounts}->{$dev}->{type} =~ m/nfs/i;
                        my $mount = $SNAG::Dispatch::shared_data->{mounts}->{$dev}->{mount};
                        my @df_output = `/bin/df -kP $mount`;

                        shift @df_output;

                        foreach my $df_line (@df_output)
                        {
                          print "$df_line";
                        }
                      }
                    },
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_df_child_stdio',
    StderrEvent  => 'supp_df_child_stderr',
    CloseEvent   => "supp_df_nfs_child_close",
  );
}

sub supp_df_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  #[root@sporkdev SystemStats]# df -k
  #Filesystem           1K-blocks      Used Available Use% Mounted on
  #/dev/sda3             67433592   7146920  56861216  12% /
  #/dev/sda1               101086     11232     84635  12% /boot
  #none                   2077280         0   2077280   0% /dev/shm
  #AFS                    9000000         0   9000000   0% /afs

  my $time = time;

  my @fields = split /\s+/, $output;

  my $mount = URI::Escape::uri_escape($fields[5]);
  $fields[4] =~ s/\%//;

  $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host . "[$mount]", 'dsk_cap', '1g', $time, $fields[1]));
  $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host . "[$mount]", 'dsk_used', '1g', $time, $fields[2]));
  $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host . "[$mount]", 'dsk_pct', '1g', $time, $fields[4]));
}

sub supp_df_child_stderr
{
}

sub supp_df_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  delete $heap->{running_states}->{run_df};
  delete $heap->{df_wheel};
}

sub supp_df_nfs_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  delete $heap->{running_states}->{run_df_nfs};
  delete $heap->{df_nfs_wheel};
}
#####################################################################################
############  IOSTAT IO  ############################################################
#####################################################################################

sub run_iostat_io
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{iostat_io_count} = (); 

  $heap->{iostat_io_wheel} = POE::Wheel::Run->new 
  (  
    Program      => [ "iostat", "-x", $stat_quanta, $stat_loops ],
    StdioFilter  => POE::Filter::Line->new(),    
    StderrFilter => POE::Filter::Line->new(),    
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_iostat_io_child_stdio',       
    StderrEvent  => 'supp_iostat_io_child_stderr',       
    CloseEvent   => "supp_iostat_io_child_close",
  );
}

sub supp_iostat_io_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  #Linux 2.4.21-27.0.4.ELsmp (spork2)      07/17/2005

  #avg-cpu:  %user   %nice    %sys %iowait   %idle
  #1.05    0.01    0.29    0.72   97.94
  #
  #Device:    rrqm/s wrqm/s   r/s   w/s  rsec/s  wsec/s    rkB/s    wkB/s avgrq-sz avgqu-sz   await  svctm  %util
  #sda          0.03   1.51  0.02  2.03    0.43   28.96     0.21    14.48    14.34     0.00    2.39   2.51   0.51
  #sda1         0.00   0.00  0.00  0.00    0.00    0.00     0.00     0.00     4.15     0.00  902.14 531.63   0.00
  #sda2         0.00   0.00  0.00  0.00    0.00    0.02     0.00     0.01    69.78     0.00  812.96 245.24   0.01
  #sda3         0.02   0.63  0.02  0.37    0.32    8.02     0.16     4.01    21.50     0.00    2.86  11.78   0.46
  #sda4         0.00   0.00  0.00  0.00    0.00    0.00     0.00     0.00     2.00     0.00   10.00  10.00   0.00
  #sda5         0.01   0.88  0.01  1.65    0.10   20.93     0.05    10.46    12.66     0.01    2.14   2.82   0.47
  #
  #avg-cpu:  %user   %nice    %sys %iowait   %idle
  #0.00    0.00    0.20    0.60   99.20
  #
  #Device:    rrqm/s wrqm/s   r/s   w/s  rsec/s  wsec/s    rkB/s    wkB/s avgrq-sz avgqu-sz   await  svctm  %util
  #sda          0.00   2.00  0.00  1.20    0.00   27.20     0.00    13.60    22.67     0.03   21.67  10.00   1.20
  #sda1         0.00   0.00  0.00  0.00    0.00    0.00     0.00     0.00     0.00     0.00    0.00   0.00   0.00
  #sda2         0.00   0.00  0.00  0.00    0.00    0.00     0.00     0.00     0.00     0.00    0.00   0.00   0.00
  #sda3         0.00   1.40  0.00  0.40    0.00   14.40     0.00     7.20    36.00     0.01   25.00  25.00   1.00
  #sda4         0.00   0.00  0.00  0.00    0.00    0.00     0.00     0.00     0.00     0.00    0.00   0.00   0.00
  #sda5         0.00   0.60  0.00  0.80    0.00   12.80     0.00     6.40    16.00     0.02   20.00  15.00   1.20
  #   0            1      2     3     4       5       6        7        8        9       10      11     12     13

  if ($output =~ /^(\w+)\s+\d+\.\d+\s+/ && $heap->{iostat_io_count}->{$1}++ >= 1)
  {
    my $time = time();
    my @stats = split /\s+/, $output;

    ### Only look at the mounted partitions, and send the mountpoint instead of the device
    if($SNAG::Dispatch::shared_data->{mounts}->{$stats[0]})
    {
      my $mp = uri_escape( $SNAG::Dispatch::shared_data->{mounts}->{$stats[0]}->{mount} );

      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'iors', "1g", $time, $stats[3]));
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'iows', "1g", $time, $stats[4]));
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'iorkbs', "1g", $time, $stats[7]));
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'iowkbs', "1g", $time, $stats[8]));
      #$kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'avgrqsz', "1g", $time, $stats[9]));
      #$kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'avgqusz', "1g", $time, $stats[10]));
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'await', "1g", $time, $stats[11]));
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'svctm', "1g", $time, $stats[12]));
    }
  }
}


sub supp_iostat_io_child_stderr
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
}

sub supp_iostat_io_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  delete $heap->{running_states}->{run_iostat_io};
  delete $heap->{iostat_io_wheel};
}

#####################################################################################
############  IOSTAT CPU  ############################################################
#####################################################################################

sub run_iostat_cpu
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{iostat_cpu_count} = 0; 
  $heap->{iostat_cpu_wheel} = POE::Wheel::Run->new 
  (  
    Program      => [ "iostat", "-c", $stat_quanta, $stat_loops ],
    StdioFilter  => POE::Filter::Line->new(),    
    StderrFilter => POE::Filter::Line->new(),    
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_iostat_cpu_child_stdio',       
    StderrEvent  => 'supp_iostat_cpu_child_stderr',       
    CloseEvent   => "supp_iostat_cpu_child_close",
  );
}

sub supp_iostat_cpu_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  # iostat  -c 5 5
  #Linux 2.4.21-27.0.4.ELsmp (spork2)      06/20/2005
  #avg-cpu:  %user   %nice    %sys %iowait   %idle
  #           0.97    0.00    0.25    0.68   98.09
  #
  #avg-cpu:  %user   %nice    %sys %iowait   %idle
  #           1.30    0.00    0.40    1.30   97.00
  #avg-cpu:  %user   %nice %system %iowait  %steal   %idle
  #           0.00    0.00    0.00   49.94    0.00   50.06
  if($output =~ s/^avg\-cpu://)
  {
    my @fields = map { s/\%//; $_ } split /\s+/, $output;

    my $fields_index;

    for (my $i; $i < $#fields; $i++)
    {
      $fields_index->{ $fields[$i] } = $i;
    }

    $heap->{fields_index} = $fields_index;
  }
  elsif ($output =~ /^\s+\d/ && $heap->{iostat_cpu_count}++ >= 1)
  {
    my $time = time();
    my @stats = split /\s+/, $output;
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'cpuuser', "1g", $time, $stats[ $heap->{fields_index}->{user} ]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'cpunic', "1g", $time, $stats[ $heap->{fields_index}->{nice} ]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'cpusys', "1g", $time, $stats[ $heap->{fields_index}->{sys} ]));

    if($heap->{fields_index}->{iowait})
    {
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'cpuiow', "1g", $time, $stats[ $heap->{fields_index}->{iowait} ]));
    }
  }

}

sub supp_iostat_cpu_child_stderr
{
}

sub supp_iostat_cpu_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  delete $heap->{running_states}->{run_iostat_cpu};
  delete $heap->{iostat_cpu_wheel};
}

#####################################################################################
############  VMSTAT  ############################################################
#####################################################################################

sub run_vmstat
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{vmstat_count} = 0;
  $heap->{vmstat_wheel} = POE::Wheel::Run->new
  (
    Program      => [ "vmstat", $stat_quanta, $stat_loops ],
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_vmstat_child_stdio',
    StderrEvent  => 'supp_vmstat_child_stderr',
    CloseEvent   => "supp_vmstat_child_close",
  );
}

sub supp_vmstat_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  # vmstat 5 5
  #procs                      memory      swap          io     system         cpu
  # r  b   swpd   free   buff  cache   si   so    bi    bo   in    cs us sy id wa
  # 0  0    160  25296 257552 1127744    0    0     0     0    4     2  1  0  4  1
  # 0  0    160  25296 257552 1127744    0    0     0    14  130    95  0  0 98  1
  # 1  2      3      4      5       6    7    8     9    10   11    12 13 14 15 16
  if ($output =~ /^\s+\d/ && $heap->{vmstat_count}++ >= 1)
  {
    my $time = time();
    my @stats = split /\s+/, $output;
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'memfree', "1g", $time, $stats[4]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'membuff', "1g", $time, $stats[5]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'memcache', "1g", $time, $stats[6]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'swapin', "1g", $time, $stats[7]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'swapout', "1g", $time, $stats[8]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'blockin', "1g", $time, $stats[9]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'blockout', "1g", $time, $stats[10]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'intrpts', "1g", $time, $stats[11]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'contxts', "1g", $time, $stats[12]));
  }
}

sub supp_vmstat_child_stderr
{
}

sub supp_vmstat_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  delete $heap->{running_states}->{run_vmstat};
  delete $heap->{vmstat_wheel};
}


#####################################################################################
############  NETSTAT  ############################################################
#####################################################################################

my %states =
(
  'CLOSING' => 'clsng',
  'ESTABLISHED' => 'est',
  'SYN_SENT' => 'syns',
  'SYN_RECV' => 'synr',
  'FIN_WAIT1' => 'finw1',
  'FIN_WAIT2' => 'finw2',
  'TIME_WAIT' => 'timew',
  'CLOSED' => 'clsd',
  'CLOSE_WAIT' => 'clsw',
  'LAST_ACK' => 'lstack',
  'LISTEN' => 'list',
  'UNKNOWN' => 'unk',
  'BOUND' => 'bound',
  'IDLE' => 'idle',
  'SYN_RCVD' => 'synr',
);

sub run_netstat
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{netstat_wheel} = POE::Wheel::Run->new
  (
    Program      => [ "/bin/netstat -an --tcp" ],
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_netstat_child_stdio',
    StderrEvent  => 'supp_netstat_child_stderr',
    CloseEvent   => "supp_netstat_child_close",
  );
}

sub supp_netstat_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
=cut
[root@mysql1 root]# netstat -an --tcp
Active Internet connections (servers and established)
Proto Recv-Q Send-Q Local Address           Foreign Address         State
tcp        0      0 129.219.19.8:3306       129.219.187.80:56829    ESTABLISHED
tcp        0      0 129.219.19.8:3306       129.219.187.80:42729    ESTABLISHED
tcp        0      0 129.219.19.8:3306       129.219.187.80:42720    ESTABLISHED

Active Internet connections (servers and established)
Proto Recv-Q Send-Q Local Address               Foreign Address             State      
tcp        0      0 0.0.0.0:2049                0.0.0.0:*                   LISTEN      
tcp        0      0 0.0.0.0:4001                0.0.0.0:*                   LISTEN      
tcp        0      0 0.0.0.0:4003                0.0.0.0:*                   LISTEN      
tcp        0      0 0.0.0.0:111                 0.0.0.0:*                   LISTEN      
tcp        0      0 0.0.0.0:724                 0.0.0.0:*                   LISTEN      
tcp        0      0 0.0.0.0:38011               0.0.0.0:*                   LISTEN      
tcp        0      0 129.219.15.207:32924        129.219.13.77:13354         TIME_WAIT   
tcp        0      0 129.219.15.207:32928        129.219.13.77:13354         ESTABLISHED 
tcp        0      0 129.219.15.207:58636        129.219.13.87:13356         TIME_WAIT   
tcp        0      0 129.219.15.207:58640        129.219.13.87:13356         ESTABLISHED 
tcp        0      0 129.219.15.207:33084        129.219.15.200:13351        TIME_WAIT   
tcp        0      0 129.219.15.207:33088        129.219.15.200:13351        ESTABLISHED 
tcp        0      0 129.219.15.207:51550        129.219.15.200:13349        ESTABLISHED 
tcp        0      0 129.219.15.207:51546        129.219.15.200:13349        TIME_WAIT   
tcp        0      0 :::22                       :::*                        LISTEN      
tcp        0      0 ::ffff:129.219.15.207:22    ::ffff:129.219.80.60:33737  ESTABLISHED 
tcp        0      0 ::ffff:129.219.15.207:22    ::ffff:129.219.80.60:50444  ESTABLISHED 
=cut


  return if $output =~ /^Active Internet connections/;
  return if $output =~ /^Proto/;

  my @fields = split /\s+/, $output;

  my ($state, $remote, $local)  = @fields[-1, -2, -3];

  $remote =~ s/^::ffff://;
  $local =~ s/^::ffff://;

  $local =~ s/^(::1|::|0.0.0.0)/\*/;

  my ($local_ip, $local_port) = split /:/, $local;

  $heap->{netstat_states}->{$state}++;

  if($state eq 'LISTEN')
  {
    $heap->{listening_ports}->{$local_port}->{$local_ip}++;
  }
  elsif($state eq 'ESTABLISHED')
  {
    my ($remote_ip, $remote_port) = split /:/, $remote;

=cut
                     '129.219.10.133' => 'vmware5.inre',
                     '10.106.150.72' => 'xen-istb1-c8-05',
                     '10.106.152.181' => 'xen-eca-vrsw5-01',
                     '10.106.140.109' => 'xenia11',
                     '10.106.140.35' => 'bbappdev1',
                     '129.219.7.82' => 'masondev1',
                     '129.219.134.209' => 'webqa',
                     '129.219.10.179' => 'xenia3',
                     '10.219.26.112' => 'cps7.wineds',
                     '10.106.164.29' => 'filesrvspare',
=cut

    if(my $host = $SNAG::Dispatch::shared_data->{remote_hosts}->{ips}->{$remote_ip})
    {

      ### Only look at activity on listening ports, Ignore SSH and SNAG connections, and ignore connections to the same host
      if( $SNAG::Dispatch::shared_data->{remote_hosts}->{ports}->{$remote_port}
          && $remote_port ne '22' 
          && $local_port ne '22' 
          && $remote_port !~ /^133[3-5]\d$/
          && !$heap->{listening_ports}->{$local_port}
          && $host ne HOST_NAME
        )
      {
        $heap->{netstat_remote_cons}->{ $host }->{$remote_port}++;
      }
    }

    if($heap->{listening_ports}->{$local_port} && $local_port ne '22' && $local_ip ne $remote_ip)
    {
      $heap->{netstat_local_cons}->{$local_port}++;
    }
  }
}

sub supp_netstat_child_stderr
{
}

sub supp_netstat_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  my $time = time();

  while(my ($state, $count) = each %{$heap->{netstat_states}})
  {
    $state = $SNAG::Source::SystemStats::netstat_states{$state} || $state;
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, (HOST_NAME, 'net_' . $state, "1g", $time, $count));
  }
  delete $heap->{netstat_states};

  while(my ($port, $count) = each %{$heap->{netstat_local_cons}})
  {
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, (HOST_NAME, 'lp_' . $port, "1g", $time, $count));
  }
  delete $heap->{netstat_local_cons};

  foreach my $host (keys %{$heap->{netstat_remote_cons}})
  {
    while( my ($port, $count) = each %{$heap->{netstat_remote_cons}->{$host}})
    {
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, (HOST_NAME, 'rcon_' . $host . '_' . $port, "1g", $time, $count));
    }
  }
  delete $heap->{netstat_remote_cons};

  $SNAG::Dispatch::shared_data->{listening_ports} = delete $heap->{listening_ports};

  delete $heap->{running_states}->{run_netstat};
  delete $heap->{netstat_wheel};
}

#####################################################################################
############  UPTIME  ############################################################
#####################################################################################

sub run_uptime
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];
  my $time = time;

  open (PROC, "</proc/uptime");
  my @stats = split(/ /, <PROC>);
  close PROC;
  $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'uptime', $rrd_min . "g", $time, $stats[0]));

  delete $heap->{running_states}->{run_uptime};
}

#####################################################################################
############  NETWORK DEVS  ############################################################
#####################################################################################

sub run_network_dev
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];
  my $time = time;

  #Inter-|   Receive                                                |  Transmit
  # face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
  #    lo:1228962397 2050962920    0    0    0     0          0         0 1228962397 2050962920    0    0    0     0       0          0
  #  eth0:1164577772 593539874    0    0    0     0          0         5 4034918522 589425585    0    0    0     0       0          0
  #  eth1:       0       0    0    0    0     0          0         0        0       0    0    0    0     0       0          0
  #####################################################################################
  # face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
  #           0          1    2    3    4     5          6         7     8          9   10   11   12    13      14         15
  open (PROC, "</proc/net/dev");
  my (@lines) = <PROC>;
  close PROC;
  foreach (@lines)
  {
    s/\s+/ /g;
    s/\s+/ /g;
    if (s/^\s*([\w\.\-]+)\s*:\s*//)
    {
      next if($1 =~ /^(vif|tap)/);
      my @stats = split(/\s+/);
      #in
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$1\]", 'inbyte', $rrd_min . "d", $time, $stats[0]));
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$1\]", 'inpkts', $rrd_min . "d", $time, $stats[1]));
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$1\]", 'inerr', $rrd_min . "d", $time, $stats[2]));
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$1\]", 'indrop', $rrd_min . "d", $time, $stats[3]));
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$1\]", 'inframe', $rrd_min . "d", $time, $stats[5]));
      #out
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$1\]", 'outbyte', $rrd_min . "d", $time, $stats[8]));
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$1\]", 'outpkts', $rrd_min . "d", $time, $stats[9]));
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$1\]", 'outerr', $rrd_min . "d", $time, $stats[10]));
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$1\]", 'outdrop', $rrd_min . "d", $time, $stats[11]));
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$1\]", 'outcoll', $rrd_min . "d", $time, $stats[13]));
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$1\]", 'outcarr', $rrd_min . "d", $time, $stats[14]));
    }
  }

  delete $heap->{running_states}->{run_network_dev};
}



#####################################################################################
############  LOADAVG  ############################################################
#####################################################################################

sub run_loadavg
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];
  my $time = time;

  open (PROC, "</proc/loadavg");
  my @stats = split(/ /, <PROC>);
  close PROC;
  $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'lavg1', $rrd_min . "g", $time, $stats[0]));
  $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'lavg5', $rrd_min . "g", $time, $stats[1]));
  #$kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'lavg15', $rrd_min . "g", $time, $stats[2]));
  $stats[3] =~ s/^\d+\///;
  $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'proc', $rrd_min . "g", $time, $stats[3]));

  delete $heap->{running_states}->{run_loadavg};
}



#####################################################################################
############  MEMINFO  ############################################################
#####################################################################################

sub run_meminfo
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];
  my $time = time;

  open (PROC, "</proc/meminfo");
  while (<PROC>)
  {
    if (/^MemTotal:\s+(\d+)/)
    {
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'memtot', $rrd_min . "g", $time, $1));
    }
    if (/^Active:\s+(\d+)/)
    {
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'memact', $rrd_min . "g", $time, $1));
    }
    elsif (/^SwapTotal:\s+(\d+)/)
    {
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'swaptot', $rrd_min . "g", $time, $1));
    }
    elsif (/^SwapFree:\s+(\d+)/)
    {
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'swapfree', $rrd_min . "g", $time, $1));
    }
    elsif (/^Committed_AS:\s+(\d+)/)
    {
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'memcomm', $rrd_min . "g", $time, $1));
    }
  }
  close PROC;

  delete $heap->{running_states}->{run_meminfo};
}


#####################################################################################
############  PROC STAT  ############################################################
#####################################################################################

my %proc_stat_stats = 
(
  'page' => 2,
  'swap' => 2,
  'processes' => 1
);

sub run_proc_stat
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  ###cpu  19048444 1915 6310550 987585646 221372549 67596 1678550
  ###page 1093045722 2070033852
  ###swap 12412104 18128079
  ###intr 876906237 309013089 2376 0 0 0 0 5 0 1....
  ###ctxt 2254554912
  ###processes 670870

  my ($stat, $val);

  open (PROC, "</proc/stat");
  my (@lines) = <PROC>;
  close PROC;
  foreach (@lines)
  {
    ($stat, $val) = m/^(\w+)\s(\d+)/;
    next unless (defined $stat && defined $proc_stat_stats{$stat});
    if ($proc_stat_stats{$stat} == 1)
    {
      $heap->{"proc_stats_$stat"} = $val;
    }
    elsif ($proc_stat_stats{$stat} == 2)
    {
      $heap->{"proc_stats_$stat-in"}  = $val;
      ($val) = m/^\w+\s+\d+\s+(\d+)/;
      $heap->{"proc_stats_$stat-out"} = $val;
    }
  }

  $kernel->delay( supp_proc_stat_collect => $rrd_step-2 );    

  delete $heap->{running_states}->{run_proc_stat};
}

sub supp_proc_stat_collect
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  my ($stat, $val, $diff_val);
  my $time = time();

  open (PROC, "</proc/stat");
  my (@lines) = <PROC>;
  close PROC;
  foreach (@lines)
  {
    ($stat, $val) = m/^(\w+)\s(\d+)/;
    next unless (defined $stat && defined $proc_stat_stats{$stat});
    if ($proc_stat_stats{$stat} == 1)
    {
      $diff_val = $val - $heap->{"proc_stats_$stat"};
      unless ($diff_val >= 0) { $diff_val = 'U'; }
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, $stat, $rrd_min . "g", $time, $diff_val));
    }
    elsif ($proc_stat_stats{$stat} == 2)
    {
      $diff_val = $val - $heap->{"proc_stats_$stat-in"};
      unless ($diff_val >= 0) { $diff_val = 'U'; }
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, $stat . "-in", $rrd_min . "g", $time, $diff_val));

      $val = m/^\w+\s+\d+\s+(\d+)/;
      $diff_val = $val - $heap->{"proc_stats_$stat-out"};
      unless ($diff_val >= 0) { $diff_val = 'U'; }
      $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, $stat . "-out", $rrd_min . "g", $time, $diff_val));
    }
  }
}

1;