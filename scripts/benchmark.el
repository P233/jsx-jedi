;;; benchmark.el --- Reproducible batch latency samples -*- lexical-binding: t; -*-

(require 'json)
(require 'cl-lib)
(load (expand-file-name "support.el" (file-name-directory load-file-name)) nil t)
(defvar jsx-jedi-benchmark-package-file
  (let ((standard-output #'external-debugging-output))
    (jsx-jedi-script-setup '(tsx))
    (jsx-jedi-script-load-package)))
(require 'typescript-ts-mode)

(defun jsx-jedi-benchmark--emit (record)
  "Write RECORD as one JSON line."
  (princ (json-serialize record))
  (terpri))

(defun jsx-jedi-benchmark--hash (file)
  "Return the SHA256 of FILE's literal bytes."
  (with-temp-buffer
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))

(defun jsx-jedi-benchmark--fixture (filler-lines target-lines)
  "Build valid JSX with FILLER-LINES outside a TARGET-LINES subtree."
  (concat
   (mapconcat (lambda (i) (format "const filler%d = <Item value={%d} />;" i i))
              (number-sequence 1 filler-lines) "\n")
   "\nconst Target = () => <Container>\n  <Section>\n"
   (mapconcat (lambda (i) (format "    <Item value={%d} />" i))
              (number-sequence 1 target-lines) "\n")
   "\n  </Section>\n</Container>;\n"))

(defun jsx-jedi-benchmark--time (function)
  "Measure one FUNCTION call, returning elapsed and GC measurements."
  (let ((start (current-time)) (count gcs-done) (gc-time gc-elapsed))
    (funcall function)
    (list (* 1000.0 (float-time (time-subtract (current-time) start)))
          (- gcs-done count) (* 1000.0 (- gc-elapsed gc-time)))))

(defun jsx-jedi-benchmark--median (samples)
  "Return the median of SAMPLES without changing their order."
  (let* ((sorted (sort (copy-sequence samples) #'<))
         (count (length sorted))
         (middle (/ count 2)))
    (if (cl-oddp count) (nth middle sorted)
      (/ (+ (nth (1- middle) sorted) (nth middle sorted)) 2.0))))

(defun jsx-jedi-benchmark--run (filler-lines target-lines samples)
  "Measure commands for a fixture, keeping setup outside SAMPLES."
  (with-temp-buffer
    (let ((source (jsx-jedi-benchmark--fixture filler-lines target-lines))
          (pulse-flag nil)
          (kill-ring nil)
          (kill-ring-yank-pointer nil)
          (inhibit-message t))
      (insert source)
      (tsx-ts-mode)
      ;; Exclude fontification and undo storage from this batch benchmark.
      (font-lock-mode -1)
      (buffer-disable-undo)
      (dolist (command '(jsx-jedi-mark jsx-jedi-copy jsx-jedi-duplicate))
        (let (command-times parse-times)
          ;; The first iteration warms each command and is not reported.
          (dotimes (index (1+ samples))
            (erase-buffer)
            (insert source)
            (treesit-buffer-root-node 'tsx)
            (syntax-propertize (point-max))
            (goto-char (point-min))
            (search-forward "<Section")
            (setq mark-active nil kill-ring nil kill-ring-yank-pointer nil)
            (garbage-collect)
            (let* ((command-time (jsx-jedi-benchmark--time command))
                   (parse-time (jsx-jedi-benchmark--time
                                (lambda () (treesit-buffer-root-node 'tsx)))))
              (when (treesit-node-check (treesit-buffer-root-node 'tsx) 'has-error)
                (error "Invalid result after %s" command))
              (if (eq command 'jsx-jedi-duplicate)
                  (unless (= 2 (length (treesit-query-capture
                                       (treesit-buffer-root-node 'tsx)
                                       '((jsx_opening_element
                                          name: (identifier) @name
                                          (:equal @name "Section"))))))
                    (error "Duplicate did not produce exactly two Sections"))
                (unless (equal source (buffer-string))
                  (error "%s changed the fixture" command)))
              (when (> index 0)
                (push (car command-time) command-times)
                (push (car parse-time) parse-times)
                (jsx-jedi-benchmark--emit
                 `((kind . "sample") (command . ,(symbol-name command))
                   (filler_lines . ,filler-lines) (target_lines . ,target-lines)
                   (sample . ,index) (command_ms . ,(nth 0 command-time))
                   (command_gc_count . ,(nth 1 command-time))
                   (command_gc_ms . ,(nth 2 command-time))
                   (post_command_parse_ms . ,(nth 0 parse-time))
                   (parse_gc_count . ,(nth 1 parse-time))
                   (parse_gc_ms . ,(nth 2 parse-time)))))))
          (jsx-jedi-benchmark--emit
           `((kind . "median") (command . ,(symbol-name command))
             (filler_lines . ,filler-lines) (target_lines . ,target-lines)
             (samples . ,samples)
             (command_ms . ,(jsx-jedi-benchmark--median command-times))
             (post_command_parse_ms . ,(jsx-jedi-benchmark--median parse-times)))))))))

(let* ((input (or (getenv "JSX_JEDI_BENCH_SAMPLES") "7"))
       (samples (string-to-number input))
       (manifest (when-let* ((directory (getenv "JSX_JEDI_GRAMMAR_DIR"))
                             (file (expand-file-name "../versions.txt" directory))
                             (_ (file-readable-p file)))
                   (with-temp-buffer (insert-file-contents file) (buffer-string)))))
  (unless (and (string-match-p "\\`[0-9]+\\'" input) (<= 1 samples 100))
    (error "JSX_JEDI_BENCH_SAMPLES must be an integer from 1 to 100"))
  (jsx-jedi-benchmark--emit
   `((kind . "environment") (emacs . ,emacs-version)
     (platform . ,system-configuration) (mode . ,(or (getenv "JSX_JEDI_TEST_MODE") "source"))
     (source_sha256 . ,(jsx-jedi-benchmark--hash
                       (expand-file-name "jsx-jedi.el" jsx-jedi-script-root)))
     (loaded_sha256 . ,(jsx-jedi-benchmark--hash jsx-jedi-benchmark-package-file))
     (dependencies . ,(or manifest "unrecorded external dependencies"))
     (library_abi . ,(treesit-library-abi-version))
     (gc_cons_threshold . ,gc-cons-threshold) (gc_cons_percentage . ,gc-cons-percentage)
     (samples . ,samples) (pulse . "disabled") (undo . "disabled")
     (font_lock . "disabled") (parser . "warm before each sample")))
  (dolist (case '((100 10) (1000 10) (10000 10)
                  (100 100) (100 1000) (100 5000)))
    (jsx-jedi-benchmark--run (car case) (cadr case) samples)))

;;; benchmark.el ends here
