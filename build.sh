set -eu

dir=analysis/paper
source=$dir/access-ice.qmd
zip=access-ice.zip

quarto render $source

cd $dir
if [ -f $zip ]; then
    rm $zip
fi 
zip -r $zip *.bst *.cls references.bib access-ice.tex access-ice_files/

