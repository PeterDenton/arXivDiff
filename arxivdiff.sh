#!/usr/bin/env bash

arXivDiff_version="v0.1.1"
echo "Welcome to arXivDiff" $arXivDiff_version
echo "by Peter Denton"
echo "(c) 2026"
echo ""

# check if necessary functions are installed
if ! [[ -x "$(command -v wget)" ]]; then
	echo "Error. wget is not installed." >&2
	exit 1
fi
if ! [[ -x "$(command -v latexdiff)" ]]; then
	echo "Error. latexdiff is not installed." >&2
	exit 1
fi
if ! [[ -x "$(command -v pdflatex)" ]]; then
	echo "Error. pdflatex is not installed." >&2
	exit 1
fi

echo "Processing user inputs..."
help_str=$'Run command as:\n  ./arxivdiff.sh xxxx.xxxxx\n to compare v1 and v2, or\n  ./arxivdiff.sh xxxx.xxxxx v3 v5\n for some arbitrary versions'
if [[ $# -eq 1 ]]; then
	first_version="v1"
	second_version="v2"
elif [[ $# -eq 3 ]]; then
	short_version_re="v[0-9]"
	long_version_re="v[0-9][0-9]"
	if [[ ! ($2 =~ $short_version_re || $2 =~ $long_version_re || $3 =~ $short_version_re || $3 =~ $long_version_re) ]]; then
		echo $help_str
	fi
	first_version=$2
	second_version=$3
else
	echo "$help_str"
	exit 1
fi

arxiv_id=$1
arxiv_new_re="^[0-9]{4}.[0-9]{5}$"
arxiv_recent_re="^[0-9]{4}.[0-9]{4}$"
if [[ ! ($arxiv_id =~ $arxiv_new_re || $arxiv_id =~ $arxiv_recent_re) ]]; then
	echo "$help_str"
	exit 1
fi

make_directory()
{
	directory_name=$1
	if [[ -d $directory_name ]]; then
		echo "Directory" $directory_name "already exists."
		read -p "Delete directory? (y/N) " response
		if [[ $response == "y" ]]; then
			echo "Removing directory"
			rm -r $directory_name
		else
			echo "Exiting."
			exit 1
		fi
	fi
	mkdir $directory_name
}

make_directory $arxiv_id
cd $arxiv_id
mkdir $first_version $second_version

process_version()
{
	version=$1
	first_bool=$2
	if [[ $first_bool -eq 1 ]]; then
		echo "Processing first version..."
	else
		echo "Processing second version..."
	fi

	cd $version
	wget -q https://arxiv.org/src/$arxiv_id$version
	if [[ ! -f $arxiv_id$version ]]; then
		echo $arxiv_id$version "does not exist. Exiting."
		exit 1
	fi
	tar -xf $arxiv_id$version
	num_tex_files=$(ls *.tex | wc -l)
	if [[ $num_tex_files -eq 0 ]]; then
		echo "No tex files found, exiting"
		exit
	elif [[ $num_tex_files -gt 1 ]]; then
		if [[ -f "main.tex" ]]; then
			main_tex_file="main.tex"
		else
			echo "Main tex file could not be identified. Exiting."
			exit 1
		fi
	else
		main_tex_file=$(ls *.tex)
	fi

	bbl_file="${main_tex_file%.tex}.bbl"
	if [[ ! -f $bbl_file ]]; then
		# Try to find the bib file
		num_bib_files=$(ls *.bib 2>/dev/null | wc -l)
		if [[ $num_bib_files -gt 1 ]]; then
			# Check if there is an obvious bib file
			main_bib_file="${main_tex_file%.tex}.bib"
			if [[ -f $main_bib_file ]]; then
				bib_file=$main_bib_file
			else
				echo "bib file could not be identified. Exiting."
				exit 1
			fi
		elif [[ $num_bib_files -eq 1 ]]; then
			bib_file=$(ls *.bib)
		fi
		if [[ -f $bib_file ]]; then
			echo "Generating bbl file from bib file"
			aux_file="${main_tex_file%.tex}.aux"
			pdflatex -interaction=batchmode $main_tex_file > /dev/null
			bibtex $aux_file > /dev/null
		fi
	fi
	if [[ $first_bool -eq 1 ]]; then
		cp $main_tex_file ../diff/first_version.tex
		if [[ -f $bbl_file ]]; then
			cp $bbl_file ../diff/first_version.bbl
		fi
	else
		cp -r * ../diff/
		cp $main_tex_file ../diff/second_version.tex
		if [[ -f $bbl_file ]]; then
			cp $bbl_file ../diff/second_version.bbl
		fi
	fi
	cd ..
}

mkdir diff
process_version $first_version 1
process_version $second_version 0

echo "Processing diff..."
cd diff
diff_tex_file=$arxiv_id$first_version$second_version.tex
diff_bbl_file=$arxiv_id$first_version$second_version.bbl
latexdiff first_version.tex second_version.tex > $diff_tex_file
if [[ -f first_version.bbl && -f second_version.bbl ]]; then
	latexdiff --allow-spaces first_version.bbl second_version.bbl > $diff_bbl_file 2> /dev/null
fi
pdflatex -interaction=batchmode $diff_tex_file > /dev/null
pdflatex -interaction=batchmode $diff_tex_file > /dev/null

if [[ -x "$(command -v xdg-open)" ]]; then
	xdg-open "${diff_tex_file%.tex}".pdf
elif [[ -x "$(command -v open)" ]]; then
	open "${diff_tex_file%.tex}".pdf
else
	echo "The diff'd pdf can be opened in" $arxiv_id/diff/$arxiv_id$first_version$second_version.pdf
fi

exit 0
