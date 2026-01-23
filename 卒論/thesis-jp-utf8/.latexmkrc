$latex = 'platex -synctex=1 -interaction=nonstopmode -file-line-error %O %S';
$bibtex = 'jbibtex %O %B';
if (system('jbibtex -version > /dev/null 2>&1') != 0) {
    $bibtex = 'bibtex %O %B';
}
$dvipdf = 'dvipdfmx %O -o %D %S';
$pdf_mode = 3;
$force_mode = 1;
