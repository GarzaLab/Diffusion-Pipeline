#!/bin/bash
#
# DWI PREPROCESSING FIRST STEP

Info="38;5;39m"
#---------------- FUNCTION: HELP ----------------#
print_help() {
echo "
USO
`basename $0` DWI_001 out-dir method
		DWI_001 	is the id of the volume to correct
		out-dir		Define the out directory
		method		LPCA or mrtrix


This script will perform Gibbs deringing, N4Biasfield correction and Denoising on the DWI.
The denoise algorithm used is LPCA from Pierric Coupé or Tourniers algorithm implemented in mrtrix.
NOTE: We require that the bvecs and bvals text files have the same DWI's id in the name, for example:
	DWI_001.nii.gz
	DWI_001.bvecs or DWI_001_bvecs.txt
	DWI_001.bvals or DWI_001_bvals.txt

NOTE: The NIFTI and the vector (bval and bvec) must be in the same directory.
NOTE: If only the b0 and one direction are provided for LPCA algorithm noise stimation will be wrong (eg. DWI PA).

PLEASE REFERENCE FOR LPCA DENOISING
Manjón, J. V., Coupé, P., Concha, L., Buades, A., Collins, D. L., & Robles, M. (2013). Diffusion weighted image denoising using overcomplete local PCA. PloS one, 8(9), e73021.

PLEASE REFERENCE FOR PCA DENOISING mrtrix
J. Veraart, D.S. Novikov, D. Christiaens, B. Ades-aron, J. Sijbers, and E. Fieremans Denoising of diffusion MRI using random matrix theory. NeuroImage 142 (2016), pp. 394–406.

Modified by kilimanjaro2
INB, August 2019
arunh.garimella@gmail.com

Original by Raul
INB, February 2019
raulrcruces@inb.unam.mx

"
}

#---------------- FUNCTION: PRINT COLOR COMMAND ----------------#
cmd() {
text=$1
echo -e "\033[38;5;105mCOMMAND --> $text \033[0m"
echo $($text)
}
#---------------- FUNCTION: PRINT ERROR ----------------#
Error() {
echo -e "\e[0;31m\n[ERROR]..... $1\n\e[0m"
}

#---------------- FUNCTION: RUN LOCAL MATLAB ----------------#
#Change these locations for your machine
run_matlab() {
local="/usr/local/Matlab16-alt/bin/matlab"
shared="/misc/mansfield/lconcha/software/MATLAB/R2016a/bin/matlab"
if [ -f $local ]
then
  echo "Running Local matlab"
  echo "  $local $@"
  $local $@
elif [ -f $shared ]
then
  echo "Running shared matlab"
  echo "  $shared $@"
  $shared $@
else
  echo "ERROR: Could not find a matlab binary."
fi
}

#---------------- WARNINGS ----------------#
# Number of inputs
if [ $# -lt 3 ]
then
	echo -e "\e[0;31m\n[ERROR]... \tAn argument is missing\n\e[0m \t\tDWI: \033[38;5;5m$1\033[0m\n\t\tOut directory: \033[38;5;5m$2\033[0m\n\t\tMethod:\033[38;5;5m$3\033[0m"
	print_help
	exit 0
fi
# Input three
if [[ $3 == "LPCA" || $3 == "mrtrix" ]]; then echo -e "\033[$Info\n\n[INFO]... Method of choice is $3 \033[0m"; else
	echo -e "\e[0;31m\n[ERROR]... \tMethod must be either LPCA or mrtrix\e[0m \n\t\tYour method: \033[38;5;5m$3\033[0m\n"; exit 0; fi


# --------------------------------------------------------------- #
# 			Starting Requirements
# --------------------------------------------------------------- #
id=$1
id=`echo $id | awk -F "." '{print $1}'`
dwi=${id}.nii.gz	# DWI in nii.gz format
bvec=`ls $id*bvec*`	# DWI associated bvec's matrix
bval=`ls $id*bval*`	# DWI associated bval's vector
out=$2			# output directory
tmp=/tmp/DWIdn4_$RANDOM	# Temporal directory
grad=${tmp}/${id}.b	# DWI vectors in mrtrix format
dngibb=${tmp}/${id}_mrgibb.nii.gz
dns=${tmp}/${id}_denoised
if [ $3 == "LPCA" ] ; then dn4=${out}/${id}_dn4.nii.gz; else dn4=${out}/${id}_dn4_mrtrix.nii.gz; fi

# Check files
if [ -f $dn4 ]; then Error "Output file already exist: $dn4'\n\e[0m"; exit 0; fi
if [ ! -f $dwi ]; then Error "$dwi must be a compressed nifti, with extension 'nii.gz'"; exit 0; else echo -e "\t[INFO]... $dwi has the correct format"; fi
if [ ! -f $bvec ]; then Error "${id}.bvec file was not found in this directory"; exit 0; else echo -e "\t[INFO]... $bvec was found"; fi
if [ ! -f $bval ]; then Error "${id}.bval file was not found in this directory"; exit 0; else echo -e "\t[INFO]... $bval was found"; fi
if [ ! -d $out ]; then Error "Directory not found: $out"; exit 2; fi

# Check number of volumes and bvecs
Nvec=`cat $bvec | wc -l`
Ndir=`/home/inb/lconcha/fmrilab_software/mrtrix3.git/bin/mrinfo -size $dwi | awk -F " " '{print $4}'`
if [ "$Ndir" != "$Nvec" ]; then Error "Missmatch between NUMBER of Volumes ($Ndir) and bvecs ($Nvec)\n\t\tTRY removing MEAN-DWI volumes"; exit 0; else echo -e "\t[INFO]... I found $Ndir dwi volumes and $Nvec bvecs"; fi


#---------------- Timer & Beginning ----------------#
aloita=$(date +%s.%N)
echo -e "\033[48;5;22m\n[INIT]... \tDiffusion Weighted Images DENOISE and & BIAS FIELD CORRECTION: ${id}\n\033[0m"


#---------------- Temporal directory ----------------#
echo  -e "\033[$Info\n[INFO]... tmp directory: \033[0m"
cmd "mkdir -v $tmp"

# --------------------------------------------------------------- #
# 			DWI REMOVE GIBBS RINGING ARITFACT
# --------------------------------------------------------------- #
echo  -e "\033[$Info\n[INFO]... Removing Gibbs Ringing Artifact \033[0m"
cmd "/home/inb/lconcha/fmrilab_software/mrtrix3.git/bin/mrdegibbs ${dwi} ${dngibb}"

# --------------------------------------------------------------- #
# 			DWI DENOISE
# --------------------------------------------------------------- #
# mrtrix Denoising Tournier algorithm
if [ $3 == "mrtrix" ] ; then
	dn4=${out}/${id}_dn4_mrtrix.nii.gz
	echo  -e "\033[$Info\n[INFO]... Running mrtrix DENOISE algorithm \033[0m"
	dns=${dns}.nii.gz
	cmd "/home/inb/lconcha/fmrilab_software/mrtrix3.git/bin/dwidenoise ${dngibb} ${dns}"
else
# LPCA denoising Pierric Coupé algorithm
# correlation is 1: correlated noise 0: white noise
# rician is 1 for bias correction and 0 to disable it
nii=${tmp}/${id}.nii
factor=1
correlation=1;
rician=1;
dns=${dns}.nii
echo  -e "\033[$Info\n[INFO]... Running LPCA-DENOISE algorithm with matlab DWIDenoisingLPCA.m \033[0m"
cmd "/home/inb/lconcha/fmrilab_software/mrtrix3.git/bin/mrconvert $dwi $nii"

# MATLAB WRAPPER
run_matlab -nodisplay <<EOF
%%%%%%%%%%%%%%%%%%%%5
warning off
addpath(genpath('/misc/mansfield/lconcha/software/DWIDenoisingPackage_r01_pcode'))
nbthread = maxNumCompThreads*2; % INTEL with old matlab

% read the data
fprintf(1,'Will now read the file: %s\n','${nii}')
V   = spm_vol('${nii}');
ima = spm_read_vols(V);

% FILTERING THE DATA
[fima,map] = DWIDenoisingLPCA(ima, $rician, nbthread, $factor, $correlation);

% SAVING THE DENOISE RESULT
fprintf(1, 'Denoised NIFTI: %s\n','${dns}')
fprintf(1, 'Residuals NIFTI: %s\n','${tmp}/${id}_residuals.nii')
fprintf(1, 'Noise estimation NIFTI: %s\n','${tmp}/${id}_noisestm.nii')
ss=size(V);
for ii=1:ss(1)

% DENOISED NIFTI
  V(ii).fname='${dns}';
  spm_write_vol(V(ii),fima(:,:,:,ii));
end

% RESIDUALS
for ii=1:ss(1)
  V(ii).fname='${tmp}/${id}_residuals.nii';
  spm_write_vol(V(ii),ima(:,:,:,ii)-fima(:,:,:,ii));
end

% NOISE ESTIMATION
for ii=1:1
  V(ii).fname='${tmp}/${id}_noisestm.nii';
  V(ii).dim=size(map);
  spm_write_vol(V(ii),map);
end
%%%%%%%%%%%%%%%%%%%%%%%%%5
EOF

fi


# --------------------------------------------------------------- #
# 		DWI mrtrix b-matrix generation
# --------------------------------------------------------------- #
echo  -e "\033[$Info\n\n[INFO]... Creando matriz de vectores en formato mrtrix \033[0m"
sed -i '/^\s*$/d' $bvec
sed -i '/^\s*$/d' $bval
paste $bvec $bval > $grad
Ncol=`awk '{print NF}' ${grad} | sort -nu | tail -n 1`
Nrow=`cat ${grad} | wc -l`
echo -e "The B-matrix has $Nrow rows & $Ncol columns"


# --------------------------------------------------------------- #
# 		DWI Bias Field Correction ANTS with mrtrix
# --------------------------------------------------------------- #
echo -e "\033[$Info\n\n[INFO]... Bias Field Correction of $i file\033[0m";
cmd "/home/inb/lconcha/fmrilab_software/mrtrix3.git/bin/dwibiascorrect -grad $grad -ants -force $dns $dn4"


# --------------------------------------------------------------- #
# 		Finish Script
# --------------------------------------------------------------- #
#----------- Removes temporal directory -----------#
echo -e "\033[$Info\n[INFO]... Removing temporal files: $tmp\e[0m"
cmd "rm -Rv $tmp"

echo  -e "\033[$Info\n[INFO]... Outfile: ${dn4} \033[0m"


#----------- Total Time -----------#
lopuu=$(date +%s.%N)
eri=$(echo "$lopuu - $aloita" | bc)
echo -e "\\033[38;5;220m \n TOTAL running time: ${eri} seconds \n \\033[0m"
