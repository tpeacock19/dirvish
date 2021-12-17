;;; dirvish-advices.el --- Shims for other packages. -*- lexical-binding: t -*-

;; This file is NOT part of GNU Emacs.

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;;; Shims for other packages.

;;; Code:

(declare-function dirvish-quit "dirvish")
(declare-function dirvish-refresh "dirvish")
(declare-function dirvish-new-frame "dirvish")
(declare-function dirvish-next-file "dirvish")
(require 'cl-lib)
(require 'dirvish-structs)
(require 'dirvish-helpers)
(require 'dirvish-header)
(require 'dirvish-preview)
(require 'dirvish-footer)
(require 'dirvish-body)
(require 'dirvish-vars)

(defun dirvish--redisplay-frame ()
  "Refresh dirvish frame, added to `after-focus-change-function'."
  (if (eq major-mode 'dirvish-mode)
      (dirvish-refresh t)
    (when (memq (previous-frame) dirvish-frame-list)
      (with-selected-frame (previous-frame)
        (dirvish-header-build)
        (dirvish-header-update)))))

(defun dirvish-setup-dired-buffer-ad (fn &rest args)
  "Apply FN with ARGS, remove the header line in Dired buffer."
  (apply fn args)
  (save-excursion
    (let ((o (make-overlay (point-min) (progn (forward-line 1) (point)))))
      (overlay-put o 'invisible t))))

(defun dirvish-refresh-ad (fn &rest args)
  "Apply FN with ARGS, rebuild dirvish frame when necessary."
  (apply fn args)
  (let ((rebuild (not (eq major-mode 'dirvish-mode))))
    (dirvish-refresh rebuild 'no-revert)))

(defun dirvish-revert-ad (fn &rest args)
  "Apply FN with ARGS then revert buffer."
  (apply fn args) (dirvish-refresh))

(defun dirvish-refresh-cursor-ad (fn &rest args)
  "Only apply FN with ARGS when editing."
  (unless (and (not (eq major-mode 'wdired-mode)) (dirvish-live-p))
    (apply fn args)))

(defun dirvish-update-line-ad (fn &rest args)
  "Apply FN with ARGS then update current line in dirvish."
  (remove-overlays (point-min) (point-max) 'dirvish-body t)
  (when-let ((pos (dired-move-to-filename nil))
             dirvish-show-icons)
    (remove-overlays (1- pos) pos 'dirvish-icons t)
    (dirvish--body-render-icon pos))
  (apply fn args)
  (dirvish-body-update t t)
  (when (dired-move-to-filename nil)
    (setf (dirvish-index-path (dirvish-meta)) (dired-get-filename nil t))
    (when (or (dirvish-header-width (dirvish-meta))
              (dirvish-one-window-p (dirvish-meta)))
      (dirvish-header-update))
    (dirvish-footer-update)
    (dirvish-debounce dirvish-preview-update dirvish-preview-delay)))

(defun dirvish-deletion-ad (fn &rest args)
  "Advice function for FN with ARGS."
  (let ((trash-directory (dirvish--get-trash-dir))) (apply fn args))
  (unless (dired-get-filename nil t) (dirvish-next-file 1))
  (dirvish-refresh))

(defun dirvish-file-open-ad (fn &rest args)
  "Apply FN with ARGS with empty `default-directory'."
  (when (dirvish-live-p) (dirvish-quit :keep-alive))
  (let ((default-directory "")) (apply fn args)))

;; FIXME: it should support window when current instance is launched by `(dirvish nil t)'
(defun dirvish-other-window-ad (fn &rest args)
  "Apply FN with ARGS in new dirvish frame."
  (let ((file (dired-get-file-for-visit)))
    (if (file-directory-p file)
        (dirvish-new-frame file)
      (apply fn args))))

(defun dirvish--update-viewports (win _)
  "Refresh attributes in viewport within WIN, added to `window-scroll-functions'."
  (let ((root-win (dirvish-root-window (dirvish-meta))))
    (when (and (eq win root-win)
               (eq (selected-frame) (window-frame root-win)))
      (with-selected-window win
        (dirvish-body-update nil t)))))

(cl-dolist (fn '(dirvish-next-file
                 dirvish-go-top
                 dirvish-go-bottom))
  (advice-add fn :around 'dirvish-update-line-ad))

(defun dirvish--add-advices ()
  "Add all advice listed in `dirvish-advice-alist'."
  (add-hook 'window-scroll-functions #'dirvish--update-viewports)
  (add-to-list 'display-buffer-alist
               '("\\(\\*info\\|\\*Help\\|\\*helpful\\|magit:\\).*"
                 (display-buffer-in-side-window)
                 (window-height . 0.4)
                 (side . bottom)))
  (add-function :after after-focus-change-function #'dirvish--redisplay-frame)
  (pcase-dolist (`(,file ,sym ,fn) dirvish-advice-alist)
    (when (require file nil t) (advice-add sym :around fn))))

(defun dirvish--clean-advices ()
  "Remove all advice listed in `dirvish-advice-alist'."
  (remove-hook 'window-scroll-functions #'dirvish--update-viewports)
  (setq display-buffer-alist (cdr display-buffer-alist))
  (remove-function after-focus-change-function #'dirvish--redisplay-frame)
  (pcase-dolist (`(,file ,sym ,fn) dirvish-advice-alist)
    (when (require file nil t) (advice-remove sym fn))))

(provide 'dirvish-advices)

;;; dirvish-advices.el ends here
