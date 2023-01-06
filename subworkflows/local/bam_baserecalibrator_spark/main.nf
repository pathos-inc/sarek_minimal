//
// PREPARE RECALIBRATION with SPARK
//
// For all modules here:
// A when clause condition is defined in the conf/modules.config to determine if the module should be run

include { GATK4_BASERECALIBRATOR_SPARK } from '../../../modules/nf-core/gatk4/baserecalibratorspark/main'
include { GATK4_GATHERBQSRREPORTS      } from '../../../modules/nf-core/gatk4/gatherbqsrreports/main'

workflow BAM_BASERECALIBRATOR_SPARK {
    take:
    cram            // channel: [mandatory] meta, cram_markduplicates, crai
    dict            // channel: [mandatory] dict
    fasta           // channel: [mandatory] fasta
    fasta_fai       // channel: [mandatory] fasta_fai
    intervals       // channel: [mandatory] intervals, num_intervals (or [], 0 if no intervals)
    known_sites     // channel: [optional]  known_sites
    known_sites_tbi // channel: [optional]  known_sites_tbi

    main:
    versions = Channel.empty()

    cram_intervals = cram.combine(intervals)
        // Move num_intervals to meta map
        .map{ meta, cram, crai, intervals, num_intervals -> [ meta + [ num_intervals:num_intervals ], cram, crai, intervals ] }

    // RUN BASERECALIBRATOR SPARK
    GATK4_BASERECALIBRATOR_SPARK(cram_intervals, fasta, fasta_fai, dict, known_sites, known_sites_tbi)

    // Figuring out if there is one or more table(s) from the same sample
    table_to_merge = GATK4_BASERECALIBRATOR_SPARK.out.table.map{ meta, table -> [ groupKey(meta, meta.num_intervals), table ]}.groupTuple().branch{
        //Warning: size() calculates file size not list length here, so use num_intervals instead
        single:   it[0].num_intervals <= 1
        multiple: it[0].num_intervals > 1
    }

    // Merge the tables only when we have intervals
    GATK4_GATHERBQSRREPORTS(table_to_merge.multiple)

    // Mix intervals and no_intervals channels together
    table_bqsr = GATK4_GATHERBQSRREPORTS.out.table.mix(table_to_merge.single.map{ meta, table -> [ meta, table[0] ] })
        // Remove no longer necessary field: num_intervals
        .map{ meta, table -> [ meta - meta.subMap('num_intervals'), table ] }

    // Gather versions of all tools used
    versions = versions.mix(GATK4_BASERECALIBRATOR_SPARK.out.versions)
    versions = versions.mix(GATK4_GATHERBQSRREPORTS.out.versions)

    emit:
    table_bqsr // channel: [ meta, table ]

    versions   // channel: [ versions.yml ]
}
