(defvar eemacs-ext/ggsh--root-dir (expand-file-name (file-name-directory load-file-name)))

(defvar eemacs-ext/ggsh--submodule-file
  (expand-file-name ".gitmodules" eemacs-ext/ggsh--root-dir))

(defvar eemacs-ext/ggsh--branch-toggle-file
  (expand-file-name "toggle-branch.sh" eemacs-ext/ggsh--root-dir))

(defvar eemacs-ext/ggsh--batch-file
  (expand-file-name "get-modules.sh" eemacs-ext/ggsh--root-dir))

(defvar eemacs-ext/ggsh--entry-head-regexp
  "^\\[submodule \"\\([^ ]+\\)\"\\]$")

(defmacro eemacs-ext/ggsh--with-submodule-buffer (&rest body)
  (let ((buffer (find-file-noselect eemacs-ext/ggsh--submodule-file)))
    `(with-current-buffer ,buffer
       ,@body)))

(defun eemacs-ext/ggsh--goto-entry-head ()
  (re-search-forward eemacs-ext/ggsh--entry-head-regexp nil t))

(defun eemacs-ext/ggsh--get-entry-region ()
  (let ((pcur (point))
        pend)
    (save-excursion
      (if (re-search-forward eemacs-ext/ggsh--entry-head-regexp
                             nil t)
          (setq pend (progn (forward-line -1)
                            (line-end-position)))
        (setq pend (point-max))))
    (cons pcur pend)))

(defun eemacs-ext/ggsh--search-pair (region)
  (let ((keys '((path . "path = \\([^ ]+\\)$")
                (url . "url = \\([^ ]+\\)$")
                (branch . "branch = \\([^ ]+\\)$")))
        matched-list
        matched-values
        format-str)
    (dolist (key keys)
      (save-excursion
        (goto-char (car region))
        (catch :matched
          (while (not (eq (point) (cdr region)))
            (when (re-search-forward (cdr key) (line-end-position) t)
              (setq matched-value (match-string-no-properties 1))
              (push (cons (car key) matched-value) matched-list)
              (throw :matched nil))
            (next-line 1)
            (forward-line 0)))))
    matched-list))

(defun eemacs-ext/ggsh--format-sh (matched-list)
  (let ((format-str (if (assoc 'branch matched-list)
                        (cons 'branch "git submodule add -b %s %s %s")
                      (cons 'non-branch "git submodule add %s %s"))))
    (cond
     ((eq (car format-str) 'branch)
      (format (cdr format-str)
              (cdr (assoc 'branch matched-list))
              (cdr (assoc 'url matched-list))
              (cdr (assoc 'path matched-list))))
     (t
      (format (cdr format-str)
              (cdr (assoc 'url matched-list))
              (cdr (assoc 'path matched-list)))))))

(defun eemacs-ext/ggsh--check-unregular (matched-list &optional fbk)
  (let ((url (cdr (assoc 'url matched-list)))
        (path (cdr (assoc 'path matched-list)))
        path-trail url-trail rtn)
    (setq path-trail
          (replace-regexp-in-string
           "^.*/\\([^ /]+\\)$" "\\1" path)
          url-trail
          (replace-regexp-in-string
           "^.*/\\([^ /]+?\\)\\(\\.git\\)?$" "\\1" url))
    (unless (equal url-trail path-trail)
      (when fbk
        (push matched-list (symbol-value fbk)))
      (setq rtn t))
    rtn))

(defun eemacs-ext/ggsh--get-submodules-list (&optional check-unregular just-check-unregular)
  (let (submodule-module-list bottom temp_match unregular)
    (eemacs-ext/ggsh--with-submodule-buffer
     (goto-char (point-min))
     (while (not (eobp))
       (setq bottom (eemacs-ext/ggsh--goto-entry-head))
       (when bottom
         (setq temp_match
               (eemacs-ext/ggsh--search-pair
                (eemacs-ext/ggsh--get-entry-region)))
         (when check-unregular
           (eemacs-ext/ggsh--check-unregular temp_match 'unregular))
         (unless just-check-unregular
           (push temp_match submodule-module-list))
         (end-of-line))
       (unless bottom
         (goto-char (point-max)))))
    (if just-check-unregular unregular
      (if check-unregular (cons submodule-module-list unregular) submodule-module-list))))

(defun eemacs-ext/ggsh--get-submodules-get-cmd-list ()
  (let ((module-list (eemacs-ext/ggsh--get-submodules-list))
        rtn)
    (dolist (el module-list)
      (push
       (eemacs-ext/ggsh--format-sh el)
       rtn))
    rtn))

(defun eemacs-ext/ggsh--gen-sh-file ()
  (interactive)
  (let ((fmtstr-list (eemacs-ext/ggsh--get-submodules-get-cmd-list))
        (inhibit-read-only t))
    (with-current-buffer (find-file-noselect eemacs-ext/ggsh--batch-file)
      (goto-char (point-min))
      (dolist (cmd fmtstr-list)
        (insert (concat cmd "\n")))
      (save-buffer)
      (kill-buffer))
    (message "Submodules getting commands generated done!")))

(defun eemacs-ext/ggsh--gen-branch-toggle-cmd ()
  (interactive)
  (let ((module-list (eemacs-ext/ggsh--get-submodules-list))
        cache
        (inhibit-read-only t)
        (flag (format-time-string "%Y%m%d%H%M%S"))
        (count 1))
    (dolist (el module-list)
      (let ((path (cdr (assoc 'path el)))
            (branch (cdr (assoc 'branch el))))
        (when branch
          (push "echo -e \"\\n==================================================\""
                cache)
          (push (format "echo \"%s: for path '%s' toggle branch to 'entropy-%s-%s'\""
                        count path branch flag)
                cache)
          (push "echo -e \"==================================================\\n\""
                cache)
          (push
           (format "cd %s && git checkout -b entropy-%s-%s && git branch -u origin/%s; cd %s"
                   path branch flag branch eemacs-ext/ggsh--root-dir)
           cache)
          (push "" cache)
          (setq count (1+ count)))))
    (setq cache (reverse cache))
    (with-current-buffer (find-file-noselect eemacs-ext/ggsh--branch-toggle-file)
      (erase-buffer)
      (goto-char (point-min))
      (dolist (el cache)
        (insert (concat el "\n")))
      (save-buffer)
      (kill-buffer))
    (message "Toggle-branch batch file generated done!")))


(provide 'eemacs-ext-submodules-parse)
