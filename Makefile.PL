use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Finance::Streamer',
    'VERSION_FROM'	=> 'lib/Finance/Streamer.pm',
    'PREREQ_PM'		=> { IO::Socket::INET 	=> 1.25,
    			     IO::Select 	=> 1.14},
);
