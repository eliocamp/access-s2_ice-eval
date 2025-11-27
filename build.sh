set -eu

dir=analysis/paper
source=$dir/access-ice.qmd

main=$dir/main.qmd 
supp=$dir/supp.qmd 
zip=access-ice.zip

cp $source $main
quarto render $main --profile main
cp $dir/main.aux $dir/ref_main.aux

cp $source $supp
quarto render $supp --profile supp
cp $dir/supp.aux $dir/ref_supp.aux

rm $main $supp 

cd $dir
pdflatex main.tex
pdflatex supp.tex



rm $zip
zip -r $zip *.bst *.csl references.bib main.tex ref_supp.aux access-ice_files/

# Clean up everything 
find . -maxdepth 1 -type f -name 'main*' ! -name 'main.pdf' ! -name 'main.tex' -exec rm {} +
find . -maxdepth 1 -type f -name 'supp*' ! -name 'supp.pdf' ! -name 'supp.tex' -exec rm {} +
