
version 1.0

task version_capture {
  input {
    String? timezone
    String docker = "us-docker.pkg.dev/general-theiagen/theiagen/alpine-plus-bash:3.20.0"
  }
  meta {
    volatile: true
  }
  command {
    PHB_Version="PHB v2.3.0"
    ~{default='' 'export TZ=' + timezone}
    date +"%Y-%m-%d" > TODAY
    echo "$PHB_Version" > PHB_VERSION
  }
  output {
    String date = read_string("TODAY")
    String phb_version = read_string("PHB_VERSION")
  }
  runtime {
    memory: "1 GB"
    cpu: 1
    docker: docker
    disks: "local-disk 10 HDD"
    dx_instance_type: "mem1_ssd1_v2_x2" 
    preemptible: 1
  }
}

task fetch_reads_name {
    input {
        File read1_lane1
        File read2_lane1
        String docker = "us-docker.pkg.dev/general-theiagen/theiagen/alpine-plus-bash:3.20.0"

    }

    command <<<
        read1_name=$(basename "~{read1_lane1}" .fastq.gz)
        read2_name=$(basename "~{read2_lane1}" .fastq.gz)

        echo $read1_name > read1_name.txt
        echo $read2_name > read2_name.txt
    >>>

    output {
        String read1_name = read_string('read1_name.txt')
        String read2_name = read_string('read2_name.txt')     
    }

    runtime {
        docker: "~{docker}"
    }

}

task cat_lanes {
  input {
    String samplename
    
    File read1_lane1
    File read1_lane2
    File? read1_lane3
    File? read1_lane4

    File? read2_lane1
    File? read2_lane2
    File? read2_lane3
    File? read2_lane4

    String read1_name
    String read2_name

    Int cpu = 2
    Int disk_size = 50
    String docker = "us-docker.pkg.dev/general-theiagen/theiagen/utility:1.2"
    Int memory = 4
  }
  meta {
    volatile: true
  }
  command <<<
    # exit task if anything throws an error (important for proper gzip format)
    set -euo pipefail
    
    exists() { [[ -f $1 ]]; }


    cat ~{read1_lane1} ~{read1_lane2} ~{read1_lane3} ~{read1_lane4} > "~{read1_name}.fastq.gz"

    if exists "~{read2_lane1}" ; then
      cat ~{read2_lane1} ~{read2_lane2} ~{read2_lane3} ~{read2_lane4} > "~{read2_name}.fastq.gz"
    fi

    # ensure newly merged FASTQs are valid gzipped format
    gzip -t "~{read1_name}.fastq.gz"
    gzip -t "~{read2_name}.fastq.gz"
  >>>
  output {
    File read1_concatenated = "~{read1_name}_merged.fastq.gz"
    File? read2_concatenated = "~{read2_name}_merged.fastq.gz"
  }

  runtime {
    docker: "~{docker}"
    memory: memory + " GB"
    cpu: cpu
    disks: "local-disk " + disk_size + " SSD"
    disk: disk_size + " GB"
    preemptible: 1
  }
}

workflow concatenate_illumina_lanes {
    input {
        String samplename 
        
        File read1_lane1 
        File read1_lane2 
        File? read1_lane3
        File? read1_lane4
        
        File read2_lane1
        File? read2_lane2
        File? read2_lane3
        File? read2_lane4
    }

    call fetch_reads_name {
        input: 
            read1_lane1 = read1_lane1,
            read2_lane1 = read2_lane1
    }

    call cat_lanes {
        input:
            samplename = samplename,
            read1_lane1 = read1_lane1,
            read2_lane1 = read2_lane1,
            read1_lane2 = read1_lane2,
            read2_lane2 = read2_lane2,
            read1_lane3 = read1_lane3,
            read2_lane3 = read2_lane3,
            read1_lane4 = read1_lane4,
            read2_lane4 = read2_lane4,
            read1_name  = fetch_reads_name.read1_name,
            read2_name = fetch_reads_name.read2_name

    }

    call version_capture {
        input:
    }

    output {
        String concatenate_illumina_lanes_version = version_capture.phb_version
        String concatenate_illumina_lanes_analysis_date = version_capture.date

        File read1 = cat_lanes.read1_concatenated
        File? read2 = cat_lanes.read2_concatenated
    }
}
