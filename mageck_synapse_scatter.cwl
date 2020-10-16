#!/usr/bin/env cwl-runner

cwlVersion: v1.0
class: Workflow

requirements:
  - class: StepInputExpressionRequirement
  - class: InlineJavascriptRequirement
  - class: MultipleInputFeatureRequirement
  - class: ScatterFeatureRequirement
  - class: SubworkflowFeatureRequirement

label: MAGeCK workflow integrated with Synapse (parallel comparisons)

inputs:
  synapse_config: File
  library_fileview: string
  output_parent_synapse_id: string
  comparisons:
    type: 
      type: array
      items: 
        type: record
        fields:
          comparison_name: string
          library_name: string
          treatment_synapse_ids: string[]
          control_synapse_ids: string[]

outputs: {}

steps:

  - id: mageck_synapse
    run: subworkflows/mageck_synapse.cwl
    scatter:
      - treatment_synapse_ids
      - control_synapse_ids
      - library_name
      - comparison_name
    scatterMethod: dotproduct
    in: 
      synapse_config: synapse_config
      library_fileview: library_fileview
      output_parent_synapse_id: output_parent_synapse_id
      treatment_synapse_ids:
        source: comparisons
        valueFrom: $(self.treatment_synapse_ids)
      control_synapse_ids:
        source: comparisons
        valueFrom: $(self.control_synapse_ids)
      library_name:
        source: comparisons
        valueFrom: $(self.library_name)
      comparison_name:
        source: comparisons
        valueFrom: $(self.comparison_name)
    out: []

$namespaces:
  s: https://schema.org/

s:author:
  - class: s:Person
    s:name: Bruno Grande
    s:email: bruno.grande@sagebase.org
    s:identifier: https://orcid.org/0000-0002-4621-1589