#!/usr/bin/env cwl-runner

cwlVersion: v1.0
class: Workflow

requirements:
  - class: StepInputExpressionRequirement
  - class: InlineJavascriptRequirement
  - class: MultipleInputFeatureRequirement
  - class: ScatterFeatureRequirement

label: Obtain Synapse IDs and download files for reference files

inputs:
  synapse_config: File
  library_fileview: string
  library_name: string
  library_filetype: 
    type:
      type: enum
      symbols:
        - library
        - nonTargetList

outputs: 
  - id: synapse_id
    type: string
    outputSource: extract_id/synapse_id
  - id: filepath
    type: File
    outputSource: syn_get/filepath

steps:

  - id: syn_query
    run: https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-tool-synapseclient/v1.1/cwl/synapse-query-tool.cwl
    in: 
      synapse_config: synapse_config
      query:
        source: [library_fileview, library_name, library_filetype]
        linkMerge: merge_flattened
        valueFrom: >
          $(
            "SELECT id FROM " + self[0] + " " +
            "WHERE LibraryName = '" + self[1] + "' " +
            "AND FileType = '" + self[2] + "'" +
            "GROUP BY id"
          )
    out:
      - query_result
  
  - id: extract_id
    run:
      class: ExpressionTool
      requirements:
        InlineJavascriptRequirement: {}
      inputs:
        query_result:
          type: File
          inputBinding:
            loadContents: true
      outputs:
        synapse_id: string
      expression: >
        $({
          "synapse_id": inputs.query_result.contents.split("\n")[1]
        })
    in: 
      query_result: syn_query/query_result
    out:
      - synapse_id

  - id: syn_get
    run: https://raw.githubusercontent.com/Sage-Bionetworks-Workflows/dockstore-tool-synapseclient/v1.1/cwl/synapse-get-tool.cwl
    in: 
      synapse_config: synapse_config
      synapseid: extract_id/synapse_id
    out:
      - filepath

$namespaces:
  s: https://schema.org/

s:author:
  - class: s:Person
    s:name: Bruno Grande
    s:email: bruno.grande@sagebase.org
    s:identifier: https://orcid.org/0000-0002-4621-1589