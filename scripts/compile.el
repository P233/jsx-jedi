;;; compile.el --- Strict package byte compilation -*- lexical-binding: t; -*-

(load (expand-file-name "support.el" (file-name-directory load-file-name)) nil t)
(require 'bytecomp)
(jsx-jedi-script-setup '(javascript typescript tsx))
(let* ((directory (jsx-jedi-script-build-directory))
       (destination (expand-file-name "jsx-jedi.elc" directory))
       (byte-compile-error-on-warn t)
       (byte-compile-dest-file-function (lambda (_) destination)))
  (make-directory directory t)
  (unless (byte-compile-file (expand-file-name "jsx-jedi.el" jsx-jedi-script-root))
    (error "Package compilation failed"))
  (princ (format "Compiled without warnings: %s\n" destination)))

;;; compile.el ends here
