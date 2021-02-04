#!/bin/bash
# Arrange outputs into BIDS format for derivatives
# https://bids-specification.readthedocs.io/en/latest/02-common-principles.html#storage-of-derived-datasets
#

inputDir=$1
outputDir=$2
sourceEntities=$3
#subjectName=$3
#sessionName=$4
templateName='template'

# derive subject and session name
subjectName=$(echo "${sourceEntities}" | cut -d '_' -f 1)
sessionName=$(echo "${sourceEntities}" | cut -d '_' -f 2)

# transfer logs
logDir="${outputDir}/logs"
mkdir -p "${logDir}"
cp "${inputDir}"/*.txt "${logDir}"/
cp "${inputDir}"/antsct_run.sh "${logDir}"/
missingTXT=${logDir}/missingFiles.txt
touch ""${missingTXT}""

# move antsCorticalThickness.sh outputs
anatDir="${outputDir}/${subjectName}/${sessionName}/anat"
mkdir -p "${anatDir}"

# function to copy files or log if they are missing
transfer () {
  cp "$1" "$2" || echo "$1" >> ""${missingTXT}""
}

# define the template for the mask json sidecar
maskTemplate='{\n"RawSources": "%s",\n"Type": "Brain"\n}'
# create the table to override BIDS default tissue label scheme
T=$(printf '\t') # encode a tab into variable
cat > "${anatDir}/${sourceEntities}_space-orig_dseg.tsv" << EOF
index $T name
1 $T Cerebrospinal Fluid
2 $T Cortical Gray Matter
3 $T White Matter
4 $T Subcortical Gray Matter
5 $T Brain Stem
6 $T Cerebellum
EOF

# Rename and copy files from the gear output/ to the anat/ directory of the BIDS derivatives dataset
transfer "${inputDir}"/*_BrainExtractionMask.nii.gz "${anatDir}/${sourceEntities}_space-orig_desc-brain_mask.nii.gz"
# shellcheck disable=SC2059
printf "${maskTemplate}" "${inputDir}/${sourceEntities}.nii.gz" > "${anatDir}/${sourceEntities}_space-orig_desc-brain_mask.json"
transfer "${inputDir}"/*_BrainNormalizedToTemplate.nii.gz "${anatDir}/${sourceEntities}_space-${templateName}_T1w.nii.gz"
transfer "${inputDir}"/*_NeckTrim.nii.gz "${anatDir}/${sourceEntities}_space-orig_desc-necktrim_T1w.nii.gz"
transfer "${inputDir}"/*_BrainSegmentation0N4.nii.gz "${anatDir}/${sourceEntities}_space-orig_desc-corrected_T1w.nii.gz"
transfer "${inputDir}"/*_ExtractedBrain0N4.nii.gz "${anatDir}/${sourceEntities}_space-orig_desc-correctedExtracted_T1w.nii.gz"
transfer "${inputDir}"/*_BrainSegmentation.nii.gz "${anatDir}/${sourceEntities}_space-orig_dseg.nii.gz"
transfer "${inputDir}"/*_CorticalThickness.nii.gz "${anatDir}/${sourceEntities}_space-orig_desc-thickness_T1w.nii.gz"
transfer "${inputDir}"/*_CorticalThicknessNormalizedToTemplate.nii.gz "${anatDir}/${sourceEntities}_space-${templateName}_desc-thickness_T1w.nii.gz"
transfer "${inputDir}"/*_CorticalMask.nii.gz "${anatDir}/${sourceEntities}_space-orig_desc-cortex_mask.nii.gz"
printf "${maskTemplate}" "${inputDir}/${sourceEntities}.nii.gz" > "${anatDir}/${sourceEntities}_space-orig_desc-cortex_mask.json"
transfer "${inputDir}"/*_RegistrationTemplateBrainMask.nii.gz "${anatDir}/${sourceEntities}_space-${templateName}_desc-brain_mask.nii.gz"
printf "${maskTemplate}" "${inputDir}/${sourceEntities}.nii.gz" > "${anatDir}/${sourceEntities}_space-${templateName}_desc-brain_mask.json"

# copy brain segmentation posteriors to anat/ then loop and rename based on label number
translateLabel () {
  # ANTs labels tissues with numbers. This function translates numbers into tissue abbreviations
  if [ "$1" = "1" ]; then
    echo "CSF"
  elif [ "$1" = "2" ]; then
    echo "CGM"
  elif [ "$1" = "3" ]; then
    echo "WM"
  elif [ "$1" = "4" ]; then
    echo "SGM"
  elif [ "$1" = "5" ]; then
    echo "BS"
  elif [ "$1" = "6" ]; then
    echo "CBM"
  else
    echo "WARNING: label number does not match known tissue class label."
    echo $1
  fi
}
cp "${inputDir}"/*_BrainSegmentationPosteriors* "${anatDir}"/
for posteriorImage in ${anatDir}/*_BrainSegmentationPosteriors*; do
  dirName=$(dirname $posteriorImage)
  baseName=$(basename $posteriorImage '.nii.gz')
  labelNumber="${baseName: -1}" # last character of string is the tissue class label number
  label=$(translateLabel $labelNumber)
  newName="${sourceEntities}_label-${label}_desc-posterior_probseg.nii.gz"
  mv $posteriorImage "${dirName}/${newName}"
done

# transforms
transfer "${inputDir}"/*_SubjectToTemplate1Warp.nii.gz "${anatDir}/${sourceEntities}_from-T1w_to-${templateName}_mode-image-xfm.nii.gz"
transfer "${inputDir}"/*_SubjectToTemplate0GenericAffine.mat "${anatDir}/${sourceEntities}_from-T1w_to-${templateName}_mode-image-xfm.mat"
transfer "${inputDir}"/*_TemplateToSubject0Warp.nii.gz "${anatDir}/${sourceEntities}_from-${templateName}_to-T1w_mode-image-xfm.nii.gz"
transfer "${inputDir}"/*_TemplateToSubject1GenericAffine.mat "${anatDir}/${sourceEntities}_from-${templateName}_to-T1w_mode-image-xfm.mat"
transfer "${inputDir}"/*_SubjectToTemplateLogJacobian.nii.gz "${anatDir}/${sourceEntities}_from-T1w_to-${templateName}_desc-logjacobian_T1w.nii.gz"

# atlas-based derivatives
cp "${inputDir}"/*.csv "${anatDir}"/ || echo "One or more csvs are missing." >> "${missingTXT}"
cp "${inputDir}"/*Lausanne* "${anatDir}"/ || echo "One or more Lausanne parcellations are missing." >> "${missingTXT}"
cp "${inputDir}"/*DKT31* "${anatDir}"/ || echo "One or more DKT31 parcellations are missing." >> "${missingTXT}"
cp "${inputDir}"/*Schaefer2018* "${anatDir}"/ || echo "One or more Schaefer parcellations are missing." >> "${missingTXT}"
cp "${inputDir}"/*BrainColor* "${anatDir}"/ || echo "BrainColor subcortical parcellation missing." >> "${missingTXT}"

# PNGs
cp "${inputDir}"/*.png "${anatDir}"/ || echo "One or more PNG images are missing." >> "${missingTXT}"

# ISSUES
#  For BrainSegmentation and BrainSegmentationPosteriors, the number of tissue classes is determined by priors;
#    so how do we automate creating the TSV lookup table and labelling the files?
#  RawSources
#  Automatically use the name of template instead of hard-coding
#  How to convey SourceEntities (i.e. prefix) in run script. Maybe parse antsct_run.sh? DONE

# IDEAS
# Do we really need json sidecars that simply say skullstripped: true? They're all skullstripped except for one which has Extracted in the filename
# Put this assumption in the README


