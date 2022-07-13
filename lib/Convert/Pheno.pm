package Convert::Pheno;

use strict;
use warnings;
use autodie;
use feature qw(say);
use Data::Dumper;
use JSON::XS;
use Path::Tiny;
use File::Basename;
use Text::CSV_XS;
use Scalar::Util qw(looks_like_number);

use constant DEVEL_MODE => 0;
use vars qw{
  $VERSION
  @ISA
  @EXPORT
};

@ISA    = qw( Exporter );
@EXPORT = qw( &write_json );

sub new {

    my ( $class, $self ) = @_;
    bless $self, $class;
    return $self;
}

############
############
#  PXF2BFF #
############
############

sub pxf2bff {

    my $self = shift;
    my $data = read_json( $self->{in_file} );

    # Get cursors for 1D terms
    my $interpretation = $data->{interpretation};
    my $phenopacket    = $data->{phenopacket};

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    # NB1: In general, we'll only load terms that exist
    # NB2: In PXF some terms are = []
    my $individual;

    # ========
    # diseases
    # ========

    $individual->{diseases} =
      [ map { $_ = { "diseaseCode" => $_->{term} } }
          @{ $phenopacket->{diseases} } ]
      if exists $phenopacket->{diseases};

    # ==
    # id
    # ==

    $individual->{id} = $phenopacket->{subject}{id}
      if exists $phenopacket->{subject}{id};

    # ====
    # info
    # ====

    # **** $data->{phenopacket} ****
    $individual->{info}{phenopacket}{dateOfBirth} =
      $phenopacket->{subject}{dateOfBirth};
    for my $term (qw (dateOfBirth genes meta_data variants)) {
        $individual->{info}{phenopacket}{$term} = $phenopacket->{$term}
          if exists $phenopacket->{$term};
    }

    # **** $data->{interpretation} ****
    $individual->{info}{interpretation}{phenopacket}{meta_data} =
      $interpretation->{phenopacket}{meta_data};

    # <diseases> and <phenotypicFeatures> are identical to those of $data->{phenopacket}{diseases,phenotypicFeatures}
    for my $term (
        qw (diagnosis diseases resolutionStatus phenotypicFeatures genes variants)
      )
    {
        $individual->{info}{interpretation}{$term} = $interpretation->{$term}
          if exists $interpretation->{$term};
    }

    # ==================
    # phenotypicFeatures
    # ==================

    $individual->{phenotypicFeatures} = [
        map {
            $_ = {
                "excluded" => (
                    exists $_->{negated} ? JSON::XS::true : JSON::XS::false
                ),
                "featureType" => $_->{type}
            }
        } @{ $phenopacket->{phenotypicFeatures} }
      ]
      if exists $phenopacket->{phenotypicFeatures};

    # ===
    # sex
    # ===

    $individual->{sex} = map_sex( $phenopacket->{subject}{sex} )
      if exists $phenopacket->{subject}{sex};

    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    # print Dumper $individual;
    return $individual;
}

############
############
#  BFF2PXF #
############
############

sub bff2pxf {
    die "Under development";
}

###############
###############
#  REDCAP2BFF #
###############
###############

sub redcap2bff {

    my $self = shift;

    # Read data from REDCap export
    my $data = read_redcap_export( $self->{in_file} );

    # Load (or read) REDCap CSV dictionary
    my $rcd = load_redcap_dictionary( $self->{'redcap_dictionary'} );

    ####################################
    # START MAPPING TO BEACON V2 TERMS #
    ####################################

    # Data structure (hashref) for all individuals
    my $individuals;

    for my $participant (@$data) {

        print Dumper $participant if $self->{debug};

        # Data structure (hashref) for each individual
        my $individual;

        # ========
        # diseases
        # ========

        $individual->{diseases} = [
            {
                "diseaseCode" => {
                    id    => 'ICD10:K51.90',
                    label => 'Inflamatory Bowel Disease'
                }
            }
        ];

        # =========
        # ethnicity
        # =========

        #print Dumper $participant and die;
        $individual->{ethnicity} = map_ethnicity(
            $rcd->{ethnicity}{_labels}{ $participant->{ethnicity} } )
          if ( exists $participant->{ethnicity}
            && $participant->{ethnicity} ne '' );    # Note that the value can be zero

        # =========
        # exposures
        # =========

        $individual->{exposures} = [];
        for my $agent (qw(alcohol)) {
            my $exposure;

            #$exposure->{ageAtExposure} = undef;
            #$exposure->{date}          = '2010-07-10';
            #$exposure->{duration}      = 'P32Y6M1D';
            $exposure->{exposureCode} = map_exposures($agent);
            $exposure->{quantity}{unit} = {
                "id"    => $participant->{alcohol},
                "label" => $rcd->{alcohol}{_labels}{ $participant->{alcohol} }
            };
            $exposure->{quantity}{value} = undef;
            push @{ $individual->{exposures} }, $exposure;
        }

        # ================
        # geographicOrigin
        # ================

        #$invididual->{geographicOrigin} = undef;

        # ==
        # id
        # ==

        #$individual->{id} = $participant->{first_name}
        #  if ( exists $participant->{first_name}
        #    && $participant->{first_name} );
        $individual->{id} = $participant->{ids_complete}
          if $participant->{ids_complete};

        # ====
        # info
        # ====

        for (qw(study_id redcap_event_name dob)) {
            $individual->{info}{$_} = $participant->{$_}
              if exists $participant->{$_};
        }

        # =========================
        # interventionsOrProcedures
        # =========================

        $individual->{interventionsOrProcedures} = [];

        #my @surgeries = map { $_ = 'surgery_details___' . $_ } ( 1 .. 8, 99 );
        my %surgery = ();
        for ( 1 .. 8, 99 ) {
            $surgery{ 'surgery_details___' . $_ } =
              $rcd->{surgery_details}{_labels}{$_};
        }
        for my $procedure ( qw(endoscopy_performed intestinal_surgery),
            keys %surgery )
        {
            if ( $participant->{$procedure} ) {
                my $intervention;
                $intervention->{ageAtProcedure} = undef;
                $intervention->{bodySite} =
                  { id => 'NCIT:C12736', label => 'intestine' };
                $intervention->{dateOfProcedure} = undef;
                $intervention->{procedureCode} =
                  map_surgery( $surgery{$procedure} )
                  if $surgery{$procedure};
                push @{ $individual->{interventionsOrProcedures} },
                  $intervention;
            }
        }

        # =============
        # karyotypicSex
        # =============

        # ========
        # measures
        # ========

        # =========
        # pedigrees
        # =========

        # ==================
        # phenotypicFeatures
        # ==================

        # ===
        # sex
        # ===

        $individual->{sex} =
          map_sex( $rcd->{sex}{_labels}{ $participant->{sex} } )
          if ( exists $participant->{sex} && $participant->{sex} );
        push @{$individuals}, $individual;

        # ==========
        # treatments
        # ==========

    }

    ##################################
    # END MAPPING TO BEACON V2 TERMS #
    ##################################

    return $individuals;
}

######################
######################
# READ REDCAP EXPORT #
######################
######################

sub read_redcap_export {

    my $in_file = shift;

    # Define split record separator
    my @exts = qw(.csv .tsv .txt);
    my ( undef, undef, $ext ) = fileparse( $in_file, @exts );

    #########################################
    #     START READING CSV|TSV|TXT FILE    #
    #########################################

    open my $fh_in, '<:encoding(utf8)', $in_file;

    # We'll read the header to assess separators in <txt> files
    chomp( my $tmp_header = <$fh_in> );

    # Defining separator
    my $separator = $ext eq '.csv'
      ? ';'    # Note we don't use comma but semicolon
      : $ext eq '.tsv' ? "\t"
      :                  ' ';

    # Defining variables
    my $data = [];                  #AoH
    my $csv  = Text::CSV_XS->new(
        {
            binary    => 1,
            auto_diag => 1,
            sep_char  => $separator
        }
    );

    # Loading header fields into $header
    $csv->parse($tmp_header);
    my $header = [ $csv->fields() ];

    # Now proceed with the rest of the file
    while ( my $row = $csv->getline($fh_in) ) {

        # We store the data as an AoH $data
        my $tmp_hash;
        for my $i ( 0 .. $#{$header} ) {
            $tmp_hash->{ $header->[$i] } = $row->[$i];
        }
        push @$data, $tmp_hash;
    }

    close $fh_in;

    #########################################
    #     END READING CSV|TSV|TXT FILE      #
    #########################################

    return $data;
}

##########################
##########################
# LOAD REDCAP DICTIONARY #
##########################
##########################

sub load_redcap_dictionary {

    my $in_file = shift;

    # Define split record separator
    my @exts = qw(.csv .tsv .txt);
    my ( undef, undef, $ext ) = fileparse( $in_file, @exts );

    #########################################
    #     START READING CSV|TSV|TXT FILE    #
    #########################################

    open my $fh_in, '<:encoding(utf8)', $in_file;

    # We'll read the header to assess separators in <txt> files
    chomp( my $tmp_header = <$fh_in> );

    # Defining separator
    my $separator =
        $ext eq '.csv' ? ';'
      : $ext eq '.tsv' ? "\t"
      :                  ' ';

    # Defining variables
    my $data = {};                  #AoH
    my $csv  = Text::CSV_XS->new(
        {
            binary    => 1,
            auto_diag => 1,
            sep_char  => $separator
        }
    );

    # Loading header fields into $header
    $csv->parse($tmp_header);
    my $header = [ $csv->fields() ];

    # Now proceed with the rest of the file
    while ( my $row = $csv->getline($fh_in) ) {

        # We store the data as an AoH $data
        my $tmp_hash;

        for my $i ( 0 .. $#{$header} ) {

            # We keep key>/value as they are
            $tmp_hash->{ $header->[$i] } = $row->[$i];

            # For the key having lavels, we create a new ad hoc key '_labels'
            # 'Choices, Calculations, OR Slider Labels' => '1, Female|2, Male|3, Other|4, not available',
            if ( $header->[$i] eq 'Choices, Calculations, OR Slider Labels' ) {
                my @tmp =
                  map { s/^\s//; s/\s+$//; $_; } ( split /\||,/, $row->[$i] );
                $tmp_hash->{_labels} = {@tmp} if @tmp % 2 == 0;
            }
        }

        # Now we create the 1D of the hash with 'Variable / Field Name'
        my $key = $tmp_hash->{'Variable / Field Name'};

        # And we nest the hash inside
        $data->{$key} = $tmp_hash;
    }

    close $fh_in;

    #######################################
    #     END READING CSV|TSV|TXT FILE    #
    #######################################

    return $data;
}

########################
########################
#  SUBROUTINES FOR I/O #
########################
########################

sub read_json {

    my $json_file = shift;
    my $str       = path($json_file)->slurp_utf8;
    my $json      = decode_json($str);              # Decode to Perl data structure
    return $json;
}

sub write_json {

    my ( $file, $json_array ) = @_;
    my $json = JSON::XS->new->utf8->canonical->pretty->encode($json_array);
    path($file)->spew_utf8($json);
    return 1;
}

############################
############################
#  SUBROUTINES FOR MAPPING #
############################
############################

sub map_ethnicity {

    my $str       = shift;
    my %ethnicity = ( map { $_ => 'NCIT:C41261' } ( 'caucasian', 'white' ) );

    # 1, Caucasian | 2, Hispanic | 3, Asian | 4, African/African-American | 5, Indigenous American | 6, Mixed | 9, Other";
    return { id => $ethnicity{ lc($str) }, label => $str };
}

sub map_sex {

    my $str = shift;
    my %sex = (
        male   => 'NCIT:C20197',
        female => 'NCIT:C16576'
    );
    return { id => $sex{ lc($str) }, label => $str };
}

sub map_exposures {

    my $str      = shift;
    my $exposure = {
        cigarretes => {
            cigarettes_days                => 'NCIT: C127064',
            'Years Have Smoked Cigarettes' => 'NCIT:C127063',
            packyears                      => 'NCIT: C73993'
        },
        alcohol => { id => 'NCIT:C16273', label => 'alcohol comsumption' }
    };
    return $exposure->{$str};
}

sub map_surgery {

    my $str = shift;

    # This is an ad hoc solution for 3TR. In the future we will use DB (SQLite) calls
    my %surgery = (
        map { $_ => 'NCIT:C15257' } ( 'ileostomy', 'ileostoma' ),
        'colonic resection'          => 'NCIT:C158758',
        colostoma                    => 'NA',
        hemicolectomy                => 'NCIT:C86074',
        'ileal/ileocoecalr esection' => 'NCIT:C158758',
        'perianal fistula surgery'   => 'NCIT:C60785',
        strictureplasty              => 'NCIT:C157993'
    );
    return { id => $surgery{ lc($str) }, label => $str };
}

1;