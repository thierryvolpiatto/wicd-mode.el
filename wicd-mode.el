;;; wicd-mode.el --- Client for the Wicd network connection manager

;;; Copyright (C) 2012, 2013 Raphaël Cauderlier <cauderlier@crans.org>

;;; Author: Raphaël Cauderlier <cauderlier@crans.org>

;;; Version: 1.1

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;; This file is *NOT* part of GNU Emacs.

;;; Commentary:
;; Installation:
;; Add these lines to your emacs init file :
; (add-to-list 'load-path "~/<path-to-wicd-mode>/")
; (require 'wicd-mode)

;; run this programme by the command
; M-x wicd

;; Description:
;; Wicd (https://launchpad.net/wicd), is a popular network
;; communication manager for linux. It is composed of a daemon
;; running as root and of clients running as unprivileged users
;; daemon and clients communicate by the D-Bus 
;; (http://www.freedesktop.org/wiki/Software/dbus) message bus
;; system. This file implements a Wicd client for Emacs using
;; the D-Bus binding for Emacs Lisp.

;; Compatibility: GNU Emacs with D-Bus binding (version 23 or higher)

;;; Code:

(require 'dbus)

;; Customization

(defgroup wicd
  nil
  "Elisp client application for the wicd network connection manager."
  :group 'applications
  )

(defcustom wicd-buffer-name "*Wicd*"
  "Name of the buffer used for listing available connections."
  :group 'wicd
  )

(defface wicd-connected
    '((t (:foreground "green")))
  "Face used to highlight connected wicd connections."
  :group 'wicd)

(defgroup wicd-dbus
  nil
  "Parameters for communication with wicd-daemon using D-Bus."
  :group 'wicd
)

(defcustom wicd-dbus-name "org.wicd.daemon"
  "Name of the main D-Bus object."
  :group 'wicd-dbus
  )

(defcustom wicd-dbus-path "/org/wicd/daemon"
  "Path of the main D-Bus object."
  :group 'wicd-dbus
  )

(defgroup wicd-wireless
  nil
  "Display of the list of available wireless connections."
  :group 'wicd
  )

(defcustom wicd-wireless-prop-list
  '(("essid" "%-24s ") ("bssid" "%17s ") ("channel" "%-7s ") ("quality" "%-3s%%"))
  "List of displayed fields with their corresponding format strings."
  :group 'wicd-wireless
  )

(defcustom wicd-wireless-filter
  ".*"
  "Regexp used as a filter to select meaningfull ESSID."
  :group 'wicd-wireless
  :type 'string
  )

;; Communication with wicd-daemon via D-BUS

(defun wicd-dbus-name (obj)
  "return name of dbus object OBJ
OBJ is one of :deamon, :wired or :wireless"
  (case obj
    (:daemon wicd-dbus-name)
    (:wired (concat wicd-dbus-name ".wired"))
    (:wireless (concat wicd-dbus-name ".wireless"))
    ))
(defun wicd-dbus-path (obj)
  "return path of dbus object OBJ
OBJ is one of :deamon, :wired or :wireless"
  (case obj
    (:daemon wicd-dbus-path)
    (:wired (concat wicd-dbus-path "/wired"))
    (:wireless (concat wicd-dbus-path "/wireless"))
    ))

(defun wicd-method (obj method)
  "Call METHOD of object OBJ without arguments
OBJ is one of :deamon, :wired or :wireless"
  (dbus-call-method :system
                    wicd-dbus-name
                    (wicd-dbus-path obj)
                    (wicd-dbus-name obj)
                    method)
  )

(defun wicd-method-arg (obj method &rest l)
  "Call METHOD of object OBJ with argument list L
OBJ is one of :deamon, :wired or :wireless"
  (apply 'dbus-call-method
         :system
         wicd-dbus-name
         (wicd-dbus-path obj)
         (wicd-dbus-name obj)
         method
         l)
  )

;; Managing the list of available wireless connections

(defun wicd-wireless-nb ()
  "Return the number of available connections."
  (wicd-method :wireless "GetNumberOfNetworks")
  )

(defun wicd-wireless-prop (id prop)
  "Return property PROP of wireless network ID"
  (wicd-method-arg :wireless "GetWirelessProperty" id prop)
  )

(defun wicd-wireless-format ()
  (apply 'concat (mapcar 'cadr wicd-wireless-prop-list))
  )

(defun wicd-wireless-header-string ()
  "String put in the header-line"
  (concat (propertize " " 'display '((space :align-to 0)))
          "#  "
          (apply 'format (wicd-wireless-format)
                 (mapcar 'car wicd-wireless-prop-list))
          )
  )

(defun wicd-wireless-header ()
  "Set the header-line to wicd-wireless-header-string"
  (setq header-line-format (wicd-wireless-header-string))
  )

(defun wicd-wireless-connected ()
  "Id of the current connection."
  (wicd-method-arg :wireless "GetCurrentNetworkID")
  )

(defun wicd-wireless-display ()
  "Redisplay wireless network list"
  (interactive)
  (switch-to-buffer wicd-buffer-name)
  (save-excursion
    (let ((buffer-read-only))
      (erase-buffer)
      (wicd-wireless-header)
      (let ((i 0)
            (n (wicd-wireless-nb))
            start)
        (while (< i n)
          (let ((essid (wicd-wireless-prop i "essid")))
            (when (string-match wicd-wireless-filter essid)
              (setq start (point))
              (insert (format "%-2d " i))
              (insert (apply 'format (wicd-wireless-format)
                             (mapcar (lambda (a)
                                       (wicd-wireless-prop i (car a)))
                                     wicd-wireless-prop-list
                                     )))
              (when (= (wicd-wireless-connected) i)
                (overlay-put (make-overlay start (point)) 'face 'wicd-connected)
                )
              (insert "\n")
              (setq i (+ 1 i))
              )))))
    )
  )

(defun wicd-wireless-disconnect ()
  "Disconnect from the current wireless network"
  (interactive)
  (wicd-method :wireless "DisconnectWireless")
  )

(defun wicd-wireless-connect (n)
  "Try to connect to wireless network number N"
  (interactive "nWireless network id: ")
  (wicd-method-arg :wireless "ConnectWireless" n)
  )

(defun wicd-wireless-connect-current-line ()
  "Try to connect to wireless network displayed on the current line of the wicd buffer"
  (interactive)
  (let* ((id (- (line-number-at-pos) 1))
         (network (wicd-wireless-prop id "essid")))
    (message "Connecting to wireless network %s with id %d." network id)
    (wicd-wireless-connect (with-current-buffer wicd-buffer-name id))
    )
  )

(defun wicd-wireless-refresh ()
  "Refresh and redisplay available wireless networks"
  (interactive)
  (wicd-method :wireless "Scan")
  (wicd-wireless-display)
  )

;; Mode definition
(defcustom wicd-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map "r" 'wicd-wireless-refresh)
    (define-key map "g" 'wicd-wireless-display)
    (define-key map "p" 'previous-line)
    (define-key map "n" 'next-line)
    (define-key map "c" 'wicd-wireless-connect-current-line)
    (define-key map "d" 'wicd-wireless-disconnect)
    (define-key map (kbd "RET") 'wicd-wireless-connect-current-line)
    map)
  "Keymap for `wicd-mode'."
  :group 'wicd
  )

(define-derived-mode
  wicd-mode
  special-mode
  "Wicd"
  :group 'wicd
  :keymap 'wicd-mode-map
  )

(add-hook 'wicd-mode-hook 'wicd-wireless-refresh)

(defun wicd ()
  "Run a wicd client in a buffer."
  (interactive)
  (pop-to-buffer wicd-buffer-name)
  (wicd-mode)
  (run-with-timer 5 nil 'wicd-wireless-refresh)
)

(provide 'wicd-mode)

;;; wicd-mode.el ends here.
