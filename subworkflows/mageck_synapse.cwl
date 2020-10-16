#!/usr/bin/env cwl-runner

cwlVersion: v1.0
class: Workflow

requirements:
  - class: StepInputExpressionRequirement
  - class: InlineJavascriptRequirement
  - class: MultipleInputFeatureRequirement
  - class: ScatterFeatureRequirement
  - class: SubworkflowFeatureRequirement

label: MAGeCK workflow integrated with Synapse

doc: >
  This workflow downloads counts files from Synapse, merges
  them into one intermediate CSV file, and uploads the MAGeCK
  output back to Synapse. MAGeCK is run in two modes: using
  median normalization and control (sgRNA) normalization. Both
  sets of results are uploaded to Synapse.

inputs:
  synapse_config: File
  library_name: string
  library_fileview: string
  treatment_synapse_ids: string[]
  control_synapse_ids: string[]
  comparison_name: string
  output_parent_synapse_id: string

outputs: {}

steps:

  - id: syn_get_treatment_counts_files
    run: https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-tool-synapseclient/v1.1/cwl/synapse-get-tool.cwl
    scatter: synapseid
    in: 
      synapse_config: synapse_config
      synapseid: treatment_synapse_ids
    out:
      - filepath
    
  - id: syn_get_control_counts_files
    run: https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-tool-synapseclient/v1.1/cwl/synapse-get-tool.cwl
    scatter: synapseid
    in: 
      synapse_config: synapse_config
      synapseid: control_synapse_ids
    out:
      - filepath
  
  - id: get_reference_library
    run: get_reference_file.cwl
    in: 
      synapse_config: synapse_config
      library_fileview: library_fileview
      library_name: library_name
      library_filetype: 
        valueFrom: library
    out:
      - synapse_id
      - filepath

  - id: get_reference_ntc
    run: get_reference_file.cwl
    in: 
      synapse_config: synapse_config
      library_fileview: library_fileview
      library_name: library_name
      library_filetype: 
        valueFrom: nonTargetList
    out:
      - synapse_id
      - filepath

  - id: merge_counts_files
    run: https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-tool-merge_counts_files/v0.0.2/cwl/merge_counts_files.cwl
    in: 
      counts_files: 
        source: [syn_get_treatment_counts_files/filepath, syn_get_control_counts_files/filepath]
        linkMerge: merge_flattened
      reference_file: get_reference_library/filepath
      output_prefix: comparison_name
    out:
      - output_file

  - id: mageck_median_norm
    run: https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-tool-mageck/v0.0.7/cwl/mageck.cwl
    in: 
      count_table: 
        source: merge_counts_files/output_file
      treatment_ids: 
        source: syn_get_treatment_counts_files/filepath
        valueFrom: $(self.map(function (f) {return f.nameroot}))
      control_ids:
        source: syn_get_control_counts_files/filepath
        valueFrom: $(self.map(function (f) {return f.nameroot}))
      output_prefix: 
        valueFrom: median_norm
      norm_method: 
        valueFrom: median
      normcounts_to_file: 
        valueFrom: $(true)
    out:
      - gene_summary
      - sgrna_summary
      - normalized_counts

  - id: mageck_control_norm
    run: https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-tool-mageck/v0.0.7/cwl/mageck.cwl
    in: 
      count_table: 
        source: merge_counts_files/output_file
      treatment_ids: 
        source: syn_get_treatment_counts_files/filepath
        valueFrom: $(self.map(function (f) {return f.nameroot}))
      control_ids:
        source: syn_get_control_counts_files/filepath
        valueFrom: $(self.map(function (f) {return f.nameroot}))
      control_sgrna:
        source: get_reference_ntc/filepath
      output_prefix: 
        valueFrom: control_norm
      norm_method: 
        valueFrom: control
      normcounts_to_file: 
        valueFrom: $(true)
    out:
      - gene_summary
      - sgrna_summary
      - normalized_counts

  - id: syn_create
    run: https://raw.githubusercontent.com/BrunoGrandePhD/dockstore-tool-synapseclient/b9404a211de1ee19da09d7ff1657f3de1db48d58/cwl/synapse-create-tool.cwl
    in: 
      - id: synapse_config
        source: synapse_config
      - id: parentid
        source: output_parent_synapse_id
      - id: name
        source: comparison_name
      - id: type
        valueFrom: Folder
    out: 
      - file_id

  - id: syn_store_median_norm
    run: https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-tool-synapseclient/v1.1/cwl/synapse-store-tool.cwl
    scatter: file_to_store
    in: 
      - id: synapse_config
        source: synapse_config
      - id: file_to_store
        source:
          - mageck_median_norm/gene_summary
          - mageck_median_norm/sgrna_summary
          - mageck_median_norm/normalized_counts
        linkMerge: merge_flattened
      - id: parentid
        source: syn_create/file_id
      - id: name
        valueFrom: $(inputs.file_to_store.basename)
      - id: used
        source: 
          - treatment_synapse_ids
          - control_synapse_ids
          - get_reference_library/synapse_id
        linkMerge: merge_flattened
      # TODO: Update URL with versioned release
      - id: executed
        valueFrom: $(["https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-workflow-mageck/master/subworkflows/mageck_synapse.cwl"])
    out: 
      - file_id
  
  - id: syn_store_control_norm
    run: https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-tool-synapseclient/v1.1/cwl/synapse-store-tool.cwl
    scatter: file_to_store
    in: 
      - id: synapse_config
        source: synapse_config
      - id: file_to_store
        source:
          - mageck_control_norm/gene_summary
          - mageck_control_norm/sgrna_summary
          - mageck_control_norm/normalized_counts
        linkMerge: merge_flattened
      - id: parentid
        source: syn_create/file_id
      - id: name
        valueFrom: $(inputs.file_to_store.basename)
      - id: used
        source: 
          - treatment_synapse_ids
          - control_synapse_ids
          - get_reference_library/synapse_id
          - get_reference_ntc/synapse_id
        linkMerge: merge_flattened
      # TODO: Update URL with versioned release
      - id: executed
        valueFrom: $(["https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-workflow-mageck/master/subworkflows/mageck_synapse.cwl"])
    out: 
      - file_id

$namespaces:
  s: https://schema.org/

s:author:
  - class: s:Person
    s:name: Bruno Grande
    s:email: bruno.grande@sagebase.org
    s:identifier: https://orcid.org/0000-0002-4621-1589
