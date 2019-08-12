;;;; utilities.lisp
;;;;
;;;; Author: appleby

(in-package #:qvm-app-ng)

(defun session-info ()
  ;; Stub implementation for FORMAT-LOG, below. See app/src/utilities.lisp for the original.
  "")

(defmacro format-log (level-or-fmt-string &rest fmt-string-or-args)
  "Send a message to syslog. If the first argument LEVEL-OR-FMT-STRING is a
keyword it is assumed to be a non-default log level (:debug), otherwise it is a control
string followed by optional args (as in FORMAT)."
  (when (keywordp level-or-fmt-string)
    ;; Sanity check that it's a valid log level at macroexpansion
    ;; time.
    (cl-syslog:get-priority level-or-fmt-string))
  (if (keywordp level-or-fmt-string)
      `(cl-syslog:format-log
        *logger*
        ',level-or-fmt-string
        "~A~@?"
        (session-info)
        ,@fmt-string-or-args)
      `(cl-syslog:format-log
        *logger*
        ':debug
        "~A~@?"
        (session-info)
        ,level-or-fmt-string
        ,@fmt-string-or-args)))

(defun check-sdk-version (&key proxy)
  "Check whether the current QVM version is older than latest Forest SDK version."
  (multiple-value-bind (available-p version)
      (sdk-update-available-p +QVM-VERSION+ :proxy proxy)
    (when available-p
      (format t "An update is available to the SDK. You have version ~A. ~
Version ~A is available from https://www.rigetti.com/forest~%"
              +QVM-VERSION+ version))
    (and available-p version)))

(defun check-libraries ()
  "Check that the foreign libraries are adequate."
  #+sbcl
  (format t "Loaded libraries:~%~{  ~A~%~}~%"
          (mapcar 'sb-alien::shared-object-pathname sb-sys:*shared-objects*))
  (unless (magicl.foreign-libraries:foreign-symbol-available-p "zuncsd_"
                                                               'magicl.foreign-libraries:liblapack)
    (format t "The loaded version of LAPACK is missing necessary functionality.~%")
    nil)
  (format t "Library check passed.~%")
  t)

(defun slurp-lines (&optional (stream *standard-input*))
  (flet ((line () (read-line stream nil nil nil)))
    (with-output-to-string (s)
      (loop :for line := (line) :then (line)
            :while line
            :do (write-line line s)))))

(defmacro with-timeout (&body body)
  (let ((f (gensym "TIME-LIMITED-BODY-")))
    `(flet ((,f () ,@body))
       (declare (dynamic-extent (function ,f)))
       (if (null *time-limit*)
           (,f)
           (bt:with-timeout (*time-limit*)
             (,f))))))

(defmacro with-timing ((var) body &body finally)
  "Evaluate the form BODY, with the execution time (ms) stored in VAR in the context of FINALLY."
  (let ((start (gensym "START-")))
    `(let ((,start (get-internal-real-time)))
       (multiple-value-prog1 ,body
         (let ((,var (round (* 1000 (- (get-internal-real-time) ,start))
                            internal-time-units-per-second)))
           (progn ,@finally))))))

(defun slurp-stream (stream)
  (with-output-to-string (s)
    (loop :for byte := (read-byte stream nil nil) :then (read-byte stream nil nil)
          :until (null byte)
          :do (write-char (code-char byte) s))))

(defun resolve-safely (filename)
  (flet ((contains-up (filename)
           (member-if (lambda (obj)
                        (or (eql ':UP obj)
                            (eql ':BACK obj)))
                      (pathname-directory filename))))
    (cond
      ((uiop:absolute-pathname-p filename)
       (error "Not allowed to specify absolute paths to INCLUDE."))

      ((uiop:relative-pathname-p filename)
       ;; Only files allowed.
       (unless (uiop:file-pathname-p filename)
         (error "INCLUDE requires a pathname to a file."))
       (when (contains-up filename)
         (error "INCLUDE can't refer to files above."))
       (if (null (gethash "safe-include-directory" *config*))
           filename
           (merge-pathnames filename (gethash "safe-include-directory" *config*))))

      (t
       (error "Invalid pathname: ~S" filename)))))

(defun safely-parse-quil-string (string)
  "Safely parse a Quil string STRING."
  (flet ((parse-it (string)
           (let* ((quil::*allow-unresolved-applications* t)
                  (parse-results
                    (quil:parse-quil string)))
             parse-results)))
    (if (null (gethash "safe-include-directory" *config*))
        (parse-it string)
        (let ((quil:*resolve-include-pathname* #'resolve-safely))
          (parse-it string)))))

(defun safely-read-quil (&optional (stream *standard-input*))
  "Safely read the Quil from the stream STREAM, defaulting to *STANDARD-INPUT*."
  (safely-parse-quil-string (slurp-lines stream)))

(defun pprint-complex (stream c &optional colonp atp)
  "A formatter for complex numbers that can be used with ~/.../."
  (declare (ignore colonp atp))
  (let ((re (realpart c))
        (im (imagpart c)))
    (cond
      ((zerop im)
       (format stream "~F" re))
      ((zerop re)
       (format stream "~Fi" im))
      ((plusp im)
       (format stream "~F+~Fi" re im))
      (t                                ; equiv: (minusp im)
       (format stream "~F-~Fi" re (- im))))))
