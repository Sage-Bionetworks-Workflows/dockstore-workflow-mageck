#!/usr/bin/env cwl-runner

cwlVersion: v1.0
class: Workflow

requirements:
  - class: StepInputExpressionRequirement
  - class: InlineJavascriptRequirement
  - class: MultipleInputFeatureRequirement
  - class: ScatterFeatureRequirement

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
  output_prefix: string
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
  
  - id: syn_get_reference_library
    run: /Users/bgrande/repos/dockstore-tool-synapseclient/cwl/synapse-get-tool.cwl
    in: 
      synapse_config: synapse_config
      # TODO: Implement query input for syn_get tool
      query:
        source: [library_fileview, library_name]
        linkMerge: merge_flattened
        valueFrom: $("SELECT id FROM " + self[0] + " WHERE LibraryName = '" + self[1] + "' AND FileType = 'library'")
    out:
      - filepath

  - id: syn_get_reference_ntc
    run: /Users/bgrande/repos/dockstore-tool-synapseclient/cwl/synapse-get-tool.cwl
    in: 
      synapse_config: synapse_config
      # TODO: Implement query input for syn_get tool
      query:
        source: [library_fileview, library_name]
        valueFrom: $("SELECT id FROM " + self[0] + " WHERE LibraryName = '" + self[1] + "' AND FileType = 'nonTargetList'")
    out:
      - filepath

  - id: merge_counts_files
    run: https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-tool-merge_counts_files/v0.0.2/cwl/merge_counts_files.cwl
    in: 
      counts_files: 
        source: [syn_get_treatment_counts_files/filepath, syn_get_control_counts_files/filepath]
        linkMerge: merge_flattened
      reference_file: syn_get_reference_library/filepath
      output_prefix: output_prefix
    out:
      - output_file

  - id: mageck_median_norm
    run: https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-tool-mageck/v0.0.6/cwl/mageck.cwl
    in: 
      count_table: 
        source: merge_counts_files/output_file
      treatment_ids: 
        source: syn_get_treatment_counts_files/filepath
        valueFrom: $(self.map(f => f.nameroot))
      control_ids:
        source: syn_get_control_counts_files/filepath
        valueFrom: $(self.map(f => f.nameroot))
      output_prefix: 
        source: output_prefix
        valueFrom: $(self + ".median_norm")
      norm_method: 
        valueFrom: median
      generate_pdf_report: 
        valueFrom: $(true)
      normcounts_to_file: 
        valueFrom: $(true)
    out:
      - gene_summary
      - normalized_counts
      - pdf_figures
      - pdf_report

  - id: mageck_control_norm
    run: https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-tool-mageck/v0.0.6/cwl/mageck.cwl
    in: 
      count_table: 
        source: merge_counts_files/output_file
      treatment_ids: 
        source: syn_get_treatment_counts_files/filepath
        valueFrom: $(self.map(f => f.nameroot))
      control_ids:
        source: syn_get_control_counts_files/filepath
        valueFrom: $(self.map(f => f.nameroot))
      control_sgrna:
        source: syn_get_reference_ntc/filepath
      output_prefix: 
        source: output_prefix
        valueFrom: $(self + ".control_norm")
      norm_method: 
        valueFrom: control
      generate_pdf_report: 
        valueFrom: $(true)
      normcounts_to_file: 
        valueFrom: $(true)
    out:
      - gene_summary
      - normalized_counts
      - pdf_figures
      - pdf_report
      - sgrna_summary

  - id: syn_store
    run: https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-tool-synapseclient/v1.1/cwl/synapse-store-tool.cwl
    scatter: file_to_store
    in: 
      - id: synapse_config
        source: synapse_config
      - id: file_to_store
        source:
          - mageck_median_norm/gene_summary
          - mageck_median_norm/normalized_counts
          - mageck_median_norm/pdf_figures
          - mageck_median_norm/pdf_report
          - mageck_control_norm/gene_summary
          - mageck_control_norm/normalized_counts
          - mageck_control_norm/pdf_figures
          - mageck_control_norm/pdf_report
          - mageck_control_norm/sgrna_summary
        linkMerge: merge_flattened
      - id: parentid
        source: output_parent_synapse_id
      - id: name
        valueFrom: $(inputs.file_to_store.basename)
      - id: used
        source: 
          - treatment_synapse_ids
          - control_synapse_ids
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