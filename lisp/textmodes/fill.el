;;; fill.el --- fill commands for Emacs

;; Maintainer: FSF
;; Last-Modified: 24 Jun 1992

;; Copyright (C) 1985, 1986, 1992 Free Software Foundation, Inc.

;; This file is part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.

;;; Code:

(defconst fill-individual-varying-indent nil
  "*Controls criterion for a new paragraph in `fill-individual-paragraphs'.
Non-nil means changing indent doesn't end a paragraph.
That mode can handle paragraphs with extra indentation on the first line,
but it requires separator lines between paragraphs.
Nil means that any change in indentation starts a new paragraph.")

(defun set-fill-prefix ()
  "Set the fill-prefix to the current line up to point.
Filling expects lines to start with the fill prefix and
reinserts the fill prefix in each resulting line."
  (interactive)
  (setq fill-prefix (buffer-substring
		     (save-excursion (beginning-of-line) (point))
		     (point)))
  (if (equal fill-prefix "")
      (setq fill-prefix nil))
  (if fill-prefix
      (message "fill-prefix: \"%s\"" fill-prefix)
    (message "fill-prefix cancelled")))

(defconst adaptive-fill-mode t
  "*Non-nil means determine a paragraph's fill prefix from its text.")

(defconst adaptive-fill-regexp "[ \t]*\\([>*] +\\)?"
  "*Regexp to match text at start of line that constitutes indentation.
If Adaptive Fill mode is enabled, whatever text matches this pattern
on the second line of a paragraph is used as the standard indentation
for the paragraph.")

(defun fill-region-as-paragraph (from to &optional justify-flag)
  "Fill region as one paragraph: break lines to fit fill-column.
Prefix arg means justify too.
From program, pass args FROM, TO and JUSTIFY-FLAG."
  (interactive "r\nP")
  ;; Don't let Adaptive Fill mode alter the fill prefix permanently.
  (let ((fill-prefix fill-prefix))
    ;; Figure out how this paragraph is indented, if desired.
    (if (and adaptive-fill-mode
	     (or (null fill-prefix) (string= fill-prefix "")))
	(save-excursion
	  (goto-char (min from to))
	  (if (eolp) (forward-line 1))
	  (forward-line 1)
	  (if (< (point) (max from to))
	      (let ((start (point)))
		(re-search-forward adaptive-fill-regexp)
		(setq fill-prefix (buffer-substring start (point))))
	    (goto-char (min from to))
	    (if (eolp) (forward-line 1))
	    ;; If paragraph has only one line, don't assume
	    ;; that additional lines would have the same starting
	    ;; decoration.  Assume no indentation.
;;	    (re-search-forward adaptive-fill-regexp)
;;	    (setq fill-prefix (make-string (current-column) ?\ ))
	    )))

    (save-restriction
      (narrow-to-region from to)
      (goto-char (point-min))
      (skip-chars-forward "\n")
      (narrow-to-region (point) (point-max))
      (setq from (point))
      (goto-char (point-max))
      (let ((fpre (and fill-prefix (not (equal fill-prefix ""))
		       (regexp-quote fill-prefix))))
	;; Delete the fill prefix from every line except the first.
	;; The first line may not even have a fill prefix.
	(and fpre
	     (progn
	       (if (>= (length fill-prefix) fill-column)
		   (error "fill-prefix too long for specified width"))
	       (goto-char (point-min))
	       (forward-line 1)
	       (while (not (eobp))
		 (if (looking-at fpre)
		     (delete-region (point) (match-end 0)))
		 (forward-line 1))
	       (goto-char (point-min))
	       (and (looking-at fpre) (forward-char (length fill-prefix)))
	       (setq from (point)))))
      ;; from is now before the text to fill,
      ;; but after any fill prefix on the first line.

      ;; Make sure sentences ending at end of line get an extra space.
      ;; loses on split abbrevs ("Mr.\nSmith")
      (goto-char from)
      (while (re-search-forward "[.?!][])}\"']*$" nil t)
	(insert ? ))

      ;; Then change all newlines to spaces.
      (subst-char-in-region from (point-max) ?\n ?\ )

      ;; Flush excess spaces, except in the paragraph indentation.
      (goto-char from)
      (skip-chars-forward " \t")
      ;; nuke tabs while we're at it; they get screwed up in a fill
      ;; this is quick, but loses when a sole tab follows the end of a sentence.
      ;; actually, it is difficult to tell that from "Mr.\tSmith".
      ;; blame the typist.
      (subst-char-in-region (point) (point-max) ?\t ?\ )
      (while (re-search-forward "   *" nil t)
	(delete-region
	 (+ (match-beginning 0)
	    (if (save-excursion
		  (skip-chars-backward " ]})\"'")
		  (memq (preceding-char) '(?. ?? ?!)))
		2 1))
	 (match-end 0)))
      (goto-char (point-max))
      (delete-horizontal-space)
      (insert "  ")
      (goto-char (point-min))

      ;; This is the actual filling loop.
      (let ((prefixcol 0) linebeg)
	(while (not (eobp))
	  (setq linebeg (point))
	  (move-to-column (1+ fill-column))
	  (if (eobp)
	      nil
	    ;; Move back to start of word.
	    (skip-chars-backward "^ \n" linebeg)
	    ;; Don't break after a period followed by just one space.
	    ;; Move back to the previous place to break.
	    ;; The reason is that if a period ends up at the end of a line,
	    ;; further fills will assume it ends a sentence.
	    ;; If we now know it does not end a sentence,
	    ;; avoid putting it at the end of the line.
	    (while (and (> (point) (+ linebeg 2))
			(eq (preceding-char) ?\ )
			(eq (char-after (- (point) 2)) ?\.))
	      (forward-char -2)
	      (skip-chars-backward "^ \n" linebeg))
	    (if (if (zerop prefixcol) (bolp) (>= prefixcol (current-column)))
		;; Keep at least one word even if fill prefix exceeds margin.
		;; This handles all but the first line of the paragraph.
		(progn
		  (skip-chars-forward " ")
		  (skip-chars-forward "^ \n"))
	      ;; Normally, move back over the single space between the words.
	      (forward-char -1)))
	    (if (and fill-prefix (zerop prefixcol)
		     (< (- (point) (point-min)) (length fill-prefix))
		     (string= (buffer-substring (point-min) (point))
			      (substring fill-prefix 0 (- (point) (point-min)))))
		;; Keep at least one word even if fill prefix exceeds margin.
		;; This handles the first line of the paragraph.
		(progn
		  (skip-chars-forward " ")
		  (skip-chars-forward "^ \n")))
	  ;; Replace all whitespace here with one newline.
	  ;; Insert before deleting, so we don't forget which side of
	  ;; the whitespace point or markers used to be on.
	  (skip-chars-backward " ")
	  (insert ?\n)
	  (delete-horizontal-space)
	  ;; Insert the fill prefix at start of each line.
	  ;; Set prefixcol so whitespace in the prefix won't get lost.
	  (and (not (eobp)) fill-prefix (not (equal fill-prefix ""))
	       (progn
		 (insert fill-prefix)
		 (setq prefixcol (current-column))))
	  ;; Justify the line just ended, if desired.
	  (and justify-flag (not (eobp))
	       (progn
		 (forward-line -1)
		 (justify-current-line)
		 (forward-line 1))))))))

(defun fill-paragraph (arg)
  "Fill paragraph at or after point.  Prefix arg means justify as well."
  (interactive "P")
  (save-excursion
    (forward-paragraph)
    (or (bolp) (newline 1))
    (let ((end (point)))
      (backward-paragraph)
      (fill-region-as-paragraph (point) end arg))))

(defun fill-region (from to &optional justify-flag)
  "Fill each of the paragraphs in the region.
Prefix arg (non-nil third arg, if called from program) means justify as well."
  (interactive "r\nP")
  (save-restriction
   (narrow-to-region from to)
   (goto-char (point-min))
   (while (not (eobp))
     (let ((initial (point))
	   (end (progn
		 (forward-paragraph 1) (point))))
       (forward-paragraph -1)
       (if (>= (point) initial)
	   (fill-region-as-paragraph (point) end justify-flag)
	 (goto-char end))))))

(defun justify-current-line ()
  "Add spaces to line point is in, so it ends at `fill-column'."
  (interactive)
  (save-excursion
   (save-restriction
    (let (ncols beg indent)
      (beginning-of-line)
      (forward-char (length fill-prefix))
      (skip-chars-forward " \t")
      (setq indent (current-column))
      (setq beg (point))
      (end-of-line)
      (narrow-to-region beg (point))
      (goto-char beg)
      (while (re-search-forward "   *" nil t)
	(delete-region
	 (+ (match-beginning 0)
	    (if (save-excursion
		 (skip-chars-backward " ])\"'")
		 (memq (preceding-char) '(?. ?? ?!)))
		2 1))
	 (match-end 0)))
      (goto-char beg)
      (while (re-search-forward "[.?!][])""']*\n" nil t)
	(forward-char -1)
	(insert ? ))
      (goto-char (point-max))
      ;; Note that the buffer bounds start after the indentation,
      ;; so the columns counted by INDENT don't appear in (current-column).
      (setq ncols (- fill-column (current-column) indent))
      (if (search-backward " " nil t)
	  (while (> ncols 0)
	    (let ((nmove (+ 3 (random 3))))
	      (while (> nmove 0)
		(or (search-backward " " nil t)
		    (progn
		     (goto-char (point-max))
		     (search-backward " ")))
		(skip-chars-backward " ")
		(setq nmove (1- nmove))))
	    (insert " ")
	    (skip-chars-backward " ")
	    (setq ncols (1- ncols))))))))

(defun fill-individual-paragraphs (min max &optional justifyp mailp)
  "Fill each paragraph in region according to its individual fill prefix.

If `fill-individual-varying-indent' is non-nil,
then a mere change in indentation does not end a paragraph.  In this mode,
the indentation for a paragraph is the minimum indentation of any line in it.

When calling from a program, pass range to fill as first two arguments.

Optional third and fourth arguments JUSTIFY-FLAG and MAIL-FLAG:
JUSTIFY-FLAG to justify paragraphs (prefix arg),
MAIL-FLAG for a mail message, i. e. don't fill header lines."
  (interactive "r\nP")
  (save-restriction
    (save-excursion
      (goto-char min)
      (beginning-of-line)
      (if mailp 
	  (while (looking-at "[^ \t\n]*:")
	    (forward-line 1)))
      (narrow-to-region (point) max)
      ;; Loop over paragraphs.
      (while (progn (skip-chars-forward " \t\n") (not (eobp)))
	(beginning-of-line)
	(let ((start (point))
	      fill-prefix fill-prefix-regexp)
	  ;; Find end of paragraph, and compute the smallest fill-prefix
	  ;; that fits all the lines in this paragraph.
	  (while (progn
		   ;; Update the fill-prefix on the first line
		   ;; and whenever the prefix good so far is too long.
		   (if (not (and fill-prefix
				 (looking-at fill-prefix-regexp)))
		       (setq fill-prefix
			     (buffer-substring (point)
					       (save-excursion (skip-chars-forward " \t") (point)))
			     fill-prefix-regexp
			     (regexp-quote fill-prefix)))
		   (forward-line 1)
		   ;; Now stop the loop if end of paragraph.
		   (and (not (eobp))
			(if fill-individual-varying-indent
			    ;; If this line is a separator line, with or
			    ;; without prefix, end the paragraph.
			    (and 
			(not (looking-at paragraph-separate))
			(save-excursion
			  (not (and (looking-at fill-prefix-regexp)
				    (progn (forward-char (length fill-prefix))
						(looking-at paragraph-separate))))))
			  ;; If this line has more or less indent
			  ;; than the fill prefix wants, end the paragraph.
			  (and (looking-at fill-prefix-regexp)
			       (save-excursion
				 (not (progn (forward-char (length fill-prefix))
					     (or (looking-at paragraph-separate)
						 (looking-at paragraph-start))))))))))
	  ;; Fill this paragraph, but don't add a newline at the end.
	  (let ((had-newline (bolp)))
	    (fill-region-as-paragraph start (point) justifyp)
	    (or had-newline (delete-char -1))))))))

;;; fill.el ends here
