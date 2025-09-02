;;; Directory Local Variables            -*- no-byte-compile: t -*-
;;; For more information see (info "(emacs) Directory Variables")

((swift-ts-mode . ((fill-column . 100)
                   (eval . (progn
                             (indent-tabs-mode 1)
                             (add-hook 'before-save-hook
                                       (lambda nil
                                         (when eglot--managed-mode (eglot-format-buffer)))
                                       nil t)))))
 (text-mode . ((eval . (auto-revert-mode)))))
