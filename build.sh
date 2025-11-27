set -eu

dir=analysis/paper
source=$dir/access-ice.qmd
zip=access-ice.zip

# main=$dir/main.qmd 
# supp=$dir/supp.qmd 


# cp $source $main
# quarto render $main --profile main
# cp $dir/main.aux $dir/ref_main.aux

# cp $source $supp
# quarto render $supp --profile supp
# cp $dir/supp.aux $dir/ref_supp.aux

# rm $main $supp 


# pdflatex main.tex
# pdflatex supp.tex

quarto render $source

cd $dir
if [ -f $zip ]; then
    rm $zip
fi 
zip -r $zip *.bst *.cls references.bib access-ice.tex access-ice_files/

