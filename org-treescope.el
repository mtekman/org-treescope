;;; org-treescope.el --- Time scoping sparse trees within org -*- lexical-binding: t; -*-

;; Copright (C) 2020 Mehmet Tekman <mtekman89@gmail.com>

;; Author: Mehmet Tekman
;; URL: https://github.com/mtekman/org-treescope.el
;; Keywords: outlines
;; Package-Requires: ((emacs "24") (org "9.2.3"))
;; Version: 0.1

;;; Commentary:

;; Navigating through an org file to see what needs to be done
;; this week and what was completed last month can be tricky.
;; This tool provides a time window to analyse your org file.

;;; Code:

;; Edit -- progn is really not necessary here, but I have no
;;         idea how to bound multiples
(require 'calendar)

;; -- variables
(defvar org-treescope--day--leftflank nil)
(defvar org-treescope--day--rightflank nil)
(defvar org-treescope--day--midpoint nil)
(defvar org-treescope--day--frommidpoint-select nil "Possible values are `<=` and `>=`.")

;; -- Init --
(defun org-treescope-initialise-reset ()
  "Reset all variables and center around current date."
  (interactive)
  (setq org-treescope--day--leftflank nil
        org-treescope--day--rightflank nil
        org-treescope--day--midpoint nil
        org-treescope--day--frommidpoint-select nil)
  (org-treescope--sensible-values)
  (org-treescope--update-all))

(defun org-treescope--sensible-values ()
  "Check that all time flankers are initialised and at sensible defaults."
  ;; We deal with absolute dates, not gregorian.
  (unless org-treescope--day--midpoint
    (setq org-treescope--day--midpoint
          (calendar-absolute-from-gregorian
           (calendar-current-date))))
  (unless org-treescope--day--leftflank (setq org-treescope--day--leftflank (- org-treescope--day--midpoint 3)))
  (unless org-treescope--day--rightflank (setq org-treescope--day--rightflank (+ org-treescope--day--midpoint 3)))
  ;; -- check sensible values --
  (if (> org-treescope--day--leftflank org-treescope--day--rightflank)
      (setq org-treescope--day--rightflank (+ org-treescope--day--leftflank 1)))
  (if (< org-treescope--day--rightflank org-treescope--day--leftflank)
      (setq org-treescope--day--leftflank (- org-treescope--day--rightflank 1))))
  ;; TODO: Add clauses for what the midpoint is doing


;; -- Date Macros
(defmacro org-treescope--defaults-and-updates (&rest innercode)
  "Set default ndays to 1 and updatenow to true, run INNERCODE, and then update-now."
  `(let ((ndays (or 1 ndays))
         (updatenow (not (or nil updatenow))))
     (progn ,@innercode
            (org-treescope--sensible-values))
     (if updatenow (org-treescope--update-all))))

(defmacro org-treescope--shift-ranges (direction lowerb upperb)
  "Call the LOWERB and UPPERB (low/up bounds) in DIRECTION.
Reset the `org-treescope--day--frommidpoint-select` to nil."
  `(org-treescope--defaults-and-updates
     (,lowerb ndays nil)
     (,upperb ndays nil)
     (setq org-treescope--day--midpoint (,direction org-treescope--day--midpoint ndays))))

(defmacro org-treescope--shift-flanks (day-flank positive)
  "Shift either the DAY-FLANK (left or right) flank in a POSITIVE or negative direction."
  `(org-treescope--defaults-and-updates
     (setq ,day-flank (,positive ,day-flank ndays))
     (if (or (< org-treescope--day--midpoint org-treescope--day--leftflank)
             (> org-treescope--day--midpoint org-treescope--day--rightflank))
         (setq org-treescope--day--midpoint ,day-flank))))

;; -- Date Methods
(defun org-treescope-day-shiftrange-backwards (&optional ndays updatenow)
  "Shift entire range back by NDAYS and update midpoint.  Redraw if UPDATENOW."
  (interactive)
  (org-treescope--shift-ranges - org-treescope-day-lowerbound-backwards org-treescope-day-upperbound-backwards))

(defun org-treescope-day-shiftrange-forwards (&optional ndays updatenow)
  "Shift entire range forwards by NDAYS and update midpoint.  Redraw if UPDATENOW."
  (interactive)
  (org-treescope--shift-ranges + org-treescope-day-lowerbound-forwards org-treescope-day-upperbound-forwards))

(defun org-treescope-day-lowerbound-forwards (&optional ndays updatenow)
  "Move left-flank by NDAYS forwards.  Redraw if UPDATENOW."
  (interactive)
  (org-treescope--shift-flanks org-treescope--day--leftflank +))

(defun org-treescope-day-lowerbound-backwards (&optional ndays updatenow)
  "Move left-flank by NDAYS backwards.  Redraw if UPDATENOW."
  (interactive)
  (org-treescope--shift-flanks org-treescope--day--leftflank -))

(defun org-treescope-day-upperbound-forwards (&optional ndays updatenow)
  "Move right-flank by NDAYS forwards.  Redraw if UPDATENOW."
  (interactive)
  (org-treescope--shift-flanks org-treescope--day--rightflank +))

(defun org-treescope-day-upperbound-backwards (&optional ndays updatenow)
  "Move right-flank by NDAYS backwards.  Redraw if UPDATENOW."
  (interactive)
  (org-treescope--shift-flanks org-treescope--day--rightflank -))

(defun org-treescope-day-frommidpoint-leftwards (&optional updatenow)
  "Ignore left and right flanks, and select all dates before midpoint.  Redraw if UPDATENOW."
  (interactive)
  (org-treescope--defaults-and-updates (setq org-treescope--day--frommidpoint-select "<=")))

(defun org-treescope-day-frommidpoint-rightwards (&optional updatenow)
  "Ignore left and right flanks, and select all dates after midpoint.  Redraw if UPDATENOW."
  (interactive)
  (org-treescope--defaults-and-updates (setq org-treescope--day--frommidpoint-select ">=")))

;; -- Update method --
(defvar org-treescope--todogroups-state nil  "Current state of TODO custom group.")
(defvar org-treescope--prioritygroups-state nil  "Current state of GROUP custom group.")

(defun org-treescope--update-datestring ()
  "Update the date string based on current state."
  ;; For some reason org-treescope--shift-ranges does not parse it unless I put it here
  (let ((format-lambda '(lambda (x) (format "%s" x))))
    (if org-treescope--day--frommidpoint-select
        (let* ((gregdate-mid (calendar-gregorian-from-absolute org-treescope--day--midpoint))
               (strdate-mid (mapconcat format-lambda (reverse gregdate-mid) "-")))
          ;; e.g. <=<2020-12-02> or >=<2019-01-31>
          (format "TIMESTAMP%s<%s>" org-treescope--day--frommidpoint-select strdate-mid))
      ;; Otherwise set a date range.
      (let ((gregdate-left  (calendar-gregorian-from-absolute org-treescope--day--leftflank))
            (gregdate-right (calendar-gregorian-from-absolute org-treescope--day--rightflank)))
        (let ((strdate-left (mapconcat format-lambda (reverse gregdate-left) "-"))
              (strdate-right (mapconcat format-lambda (reverse gregdate-right) "-")))
          (format "TIMESTAMP>=<%s>&TIMESTAMP<=<%s>" strdate-left strdate-right))))))

(defun org-treescope--update-all (&optional silent)
  "Update the dates, todos, priorities and show on calendar if not SILENT."
  (let ((priority-string
         (if org-treescope--prioritygroups-state
             (eval `(format "PRIORITY>=%s&PRIORITY<=%s"
                            ,@org-treescope--prioritygroups-state))))
        (todo-string
         (if org-treescope--todogroups-state
             (let* ((string-fmt
                     (mapconcat 'identity
                                org-treescope--todogroups-state "\\|")))
               (format "TODO={%s}" string-fmt))))
        (date-string (org-treescope--update-datestring)))
    (unless silent (org-treescope--update-calendar))
    (setq org-treescope--day--frommidpoint-select nil)
    (let* ((slist `(,date-string ,todo-string ,priority-string))
           (mlist (--filter (if it it) slist))
           (formt (mapconcat 'identity mlist "&"))) ;; TODO: Become a + for priority
      (message formt))))

;; --- Todos and Priorities ---
(defcustom org-treescope--todogroups
  '(nil ("DONE") ("TODO" "DOING") ("TODO" "DONE") ("WAITING"))
  "List of TODO groups to show in buffer.  A value of nil shows all."
  :type 'list
  :group 'treescope)

(defcustom org-treescope--prioritygroups
  '(nil (65 68) (65 70) (70 75))
  "List of PRIORITY ranges (lowest highest) to show in buffer.  A value of nil shows all."
  :type 'list
  :group 'treescope)

(defmacro org-treescope--next-state (statecurrent statelist direction)
  "Set the next state in the STATELIST from the STATECURRENT, cycling in DIRECTION."
  `(let* ((now-index (or (cl-position ,statecurrent ,statelist :test 'equal) 0))
          (nxt-index (mod (,direction now-index 1) (length ,statelist)))
          (nxt-state (nth nxt-index ,statelist)))
     (setq ,statecurrent nxt-state)
     (org-treescope--update-all t)))

(defun org-treescope-cycle-todostates-forwards ()
  "Cycle the TODO groups given by the `org-treescope--todogroups` variable forward."
  (interactive)
  (org-treescope--next-state org-treescope--todogroups-state org-treescope--todogroups +))

(defun org-treescope-cycle-todostates-backwards ()
  "Cycle the TODO groups given by the `org-treescope--todogroups` variable forward."
  (interactive)
  (org-treescope--next-state org-treescope--todogroups-state org-treescope--todogroups -))

(defun org-treescope-cycle-prioritystates-forwards ()
  "Cycle the PRIORITY groups given by the `org-treescope--todogroups` variable forward."
  (interactive)
  (org-treescope--next-state org-treescope--prioritygroups-state org-treescope--prioritygroups +))

(defun org-treescope-cycle-prioritystates-backwards ()
  "Cycle the PRIORITY groups given by the `org-treescope--todogroups` variable forward."
  (interactive)
  (org-treescope--next-state org-treescope--prioritygroups-state org-treescope--prioritygroups -))

;; -- Calendar Functions
(defmacro org-treescope--markdate (abs face)
  "Takes an ABS date and highlight it on the calendar with FACE."
  `(calendar-mark-visible-date (calendar-gregorian-from-absolute ,abs) ,face))

(defun org-treescope--update-calendar ()
  "Show and update the calendar to show the left, right, and middle flanks."
  (unless (member "*Calendar*"
                  (--map (buffer-name (window-buffer it)) (window-list)))
    ;; if calendar not open
    (calendar))
  (org-treescope-mode7 t)
  (calendar-unmark)
  (if org-treescope--day--frommidpoint-select
      ;; TODO: Full left or Full Right
      (message "fixme")
    ;; Normal Flanking Range
    (dolist (absdate (number-sequence org-treescope--day--leftflank org-treescope--day--rightflank))
      (cond
       ((eq absdate org-treescope--day--midpoint) (org-treescope--markdate org-treescope--day--midpoint org-treescope-midday-marker))
       (t (org-treescope--markdate absdate org-treescope-range-marker))))))

(define-minor-mode org-treescope-mode7
  "Test"
  :init-value nil
  :lighter " scope"
  :keymap
  '(([left] . org-treescope-day-shiftrange-backwards)
    ([right] . org-treescope-day-shiftrange-forwards)
    ([C-left] . org-treescope-day-lowerbound-backwards)
    ([C-right] . org-treescope-day-lowerbound-forwards)
    ([M-left] . org-treescope-day-upperbound-backwards)
    ([M-right] . org-treescope-day-upperbound-forwards)
    ([C-M-left] . org-treescope-day-frommidpoint-leftwards)
    ([C-M-right] . org-treescope-day-frommidpoint-rightwards)
    ([C-up] . org-treescope-cycle-todostates-forwards)
    ([C-down] . org-treescope-cycle-todostates-backwards)
    ([M-up] . org-treescope-cycle-prioritystates-forwards)
    ([M-down] . org-treescope-cycle-prioritystates-backwards)
    ([down] . org-treescope-initialise-reset)))

;; -- Faces --
(defface org-treescope-marker-range
  '((((class color) (background light))
     :background "darkblue")
    (((class color) (background dark))
     :background "darkblue")
    (t :inverse-video t))
  "Face for showing the range markers."
  :group 'treescope-faces)

(defface org-treescope-marker-midday
  '((((class color) (background light))
     :background "green")
    (((class color) (background dark))
     :background "green")
    (t :inverse-video t))
  "Face for showing the middle marker."
  :group 'treescope-faces)

(defcustom org-treescope-range-marker 'org-treescope-marker-range
  "How to highlight all days covered by the ranges in the calendar."
  :type '(choice (string :tag "Single character string") face)
  :group 'treescope)

(defcustom org-treescope-midday-marker 'org-treescope-marker-midday
  "How to highlight all days covered by the ranges in the calendar."
  :type '(choice (string :tag "Single character string") face)
  :group 'treescope)

(provide 'org-treescope)
;;; org-treescope.el ends here
