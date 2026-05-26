;;;; calendar.lisp  (Common Lisp)

(defparameter *month-names*
  #("January" "February" "March" "April" "May" "June"
    "July" "August" "September" "October" "November" "December"))

(defun leap-year-p (y)
  (and (zerop (mod y 4))
       (or (not (zerop (mod y 100)))
           (zerop (mod y 400)))))

(defun days-in-month (y m)
  (aref #(0 31 28 31 30 31 30 31 31 30 31 30 31)
        (if (and (= m 2) (leap-year-p y)) 13 m))
  (cond
    ((= m 2) (if (leap-year-p y) 29 28))
    ((member m '(1 3 5 7 8 10 12)) 31)
    (t 30)))

;; Day of week for Gregorian dates: 0=Sunday..6=Saturday
;; Sakamoto algorithm (works for Gregorian calendar)
(defun day-of-week (y m d)
  (let* ((t #(0 3 2 5 0 3 5 1 4 6 2 4))
         (y2 (if (< m 3) (1- y) y)))
    (mod (+ y2 (floor y2 4) (- (floor y2 100)) (floor y2 400)
            (aref t (1- m)) d)
         7)))

(defun pad (n) (make-string n :initial-element #\Space))

(defun print-month (y m &key (week-start :sunday))
  (let* ((title (format nil "~A ~D" (aref *month-names* (1- m)) y))
         (dim (days-in-month y m))
         (dow0 (day-of-week y m 1))
         ;; shift if weeks start Monday
         (offset (if (eq week-start :monday)
                     (mod (- dow0 1) 7)
                     dow0)))
    (format t "~&~A~%" (pad (max 0 (floor (- 20 (length title)) 2))))
    (format t "~A~%" title)
    (format t (if (eq week-start :monday)
                  "Mo Tu We Th Fr Sa Su~%"
                  "Su Mo Tu We Th Fr Sa~%"))
    ;; initial padding
    (dotimes (_ offset) (format t "   "))
    ;; days
    (loop for d from 1 to dim do
      (format t "~2D " d)
      (let* ((cell (+ offset d))
             (end-of-week (zerop (mod cell 7))))
        (when end-of-week (terpri))))
    (terpri)))

;; Example:
;; (print-month 2026 2)
;; (print-month 2026 2 :week-start :monday)
