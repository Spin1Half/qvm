;;;; app-ng/src/validators.lisp
;;;;
;;;; Author: appleby
(in-package #:qvm-app-ng)

(defun optionally (parameter-parser)
  "Combinator for parsing optional parameters.

PARAMETER-PARSER is a function-designator for a function that accepts a single required argument.

Return a function that accepts a single PARAMETER and calls PARAMETER-PARSER on it if PARAMETER is non-NIL. Otherwise, return NIL."
  (lambda (parameter)
    (and parameter (funcall parameter-parser parameter))))

(defun %parse-uuid-token (token token-type-name)
  ;; Ensure it's a STRING before attempting to canonicalize the case. Otherwise, we'll get a
  ;; not-so-helpful error message.
  (unless (typep token 'string)
    (user-input-error "Invalid ~A token. Expected a v4 UUID string. Got ~S"
                      token-type-name token))

  (let ((canonicalized-token (canonicalize-uuid-string token)))
    (unless (valid-uuid-string-p canonicalized-token)
      (user-input-error "Invalid ~A token. Expected a v4 UUID. Got ~S"
                        token-type-name token))
    canonicalized-token))

(defun parse-qvm-token (qvm-token)
  (%parse-uuid-token qvm-token "persistent QVM"))

(defun parse-job-token (job-token)
  (%parse-uuid-token job-token "JOB"))

(defun %parse-string-to-known-symbol (parameter-name parameter-string known-symbols
                                      &optional (package 'qvm-app-ng))
  (flet ((%error ()
           (user-input-error "Invalid ~A. Expected one of: ~{~S~^, ~}. Got ~S"
                             parameter-name
                             (mapcar #'string-downcase known-symbols)
                             parameter-string)))
    (unless (typep parameter-string 'string)
      (%error))
    (let ((symbol (find-symbol (string-upcase parameter-string) package)))
      (unless (and symbol (member symbol known-symbols))
        (%error))
      symbol)))

(defun parse-simulation-method (simulation-method)
  (%parse-string-to-known-symbol 'simulation-method simulation-method +available-simulation-methods+))

(defun parse-log-level (log-level)
  (%parse-string-to-known-symbol 'log-level log-level +available-log-levels+ 'keyword))

(defun parse-allocation-method (allocation-method)
  (%parse-string-to-known-symbol 'allocation-method allocation-method +available-allocation-methods+))

(defun parse-num-qubits (num-qubits)
  (unless (typep num-qubits '(integer 0))
    (user-input-error "Invalid NUM-QUBITS. Expected a non-negative integer. Got ~S"
                      num-qubits))
  num-qubits)

(defun valid-address-query-p (addresses)
  "Is ADDRESSES a valid address query HASH-TABLE?

Return T if ADDRESSES is a HASH-TABLE whose keys are STRINGs denoting DECLAREd memory names and whose values are either T or else a list of non-negative integers."
  (cond
    ((not (hash-table-p addresses)) nil)
    (t
     (maphash (lambda (k v)
                (unless (and (stringp k)
                             (or (eq t v)
                                 (and (alexandria:proper-list-p v)
                                      (every #'integerp v)
                                      (notany #'minusp v))))
                  (return-from valid-address-query-p nil)))
              addresses)
     t)))

(defun valid-memory-contents-query-p (memory-contents)
  "Is MEMORY-CONTENTS a valid memory-contents query HASH-TABLE?

Return T if MEMORY-CONTENTS is a HASH-TABLE whose keys are STRINGs denoting DECLAREd memory names and whose values are a LIST of LISTs of length 2 where the first element of each pair is a non-negative INTEGER and the second element is either an INTEGER or REAL."
  (cond
    ((not (hash-table-p memory-contents)) nil)
    (t
     (maphash (lambda (k v)
                (unless (and (stringp k)
                             (and (alexandria:proper-list-p v)
                                  (every (lambda (entry)
                                           (and (alexandria:proper-list-p entry)
                                                (= 2 (length entry))
                                                (integerp (first entry))
                                                (not (minusp (first entry)))
                                                (typep (second entry) '(or integer real))))
                                         v)))
                  (return-from valid-memory-contents-query-p nil)))
              memory-contents)
     t)))

(defun parse-addresses (addresses)
  (unless (valid-address-query-p addresses)
    (user-input-error
     "Invalid ADDRESSES parameter. The requested addresses should be a JSON object whose keys are ~
      DECLAREd memory names, and whose values are either the true value to request all memory, or ~
      a list of non-negative integer indexes to request only the memory locations corresponding ~
      to the given indexes."))
  addresses)

(defun parse-memory-contents (memory-contents)
  (unless (valid-memory-contents-query-p memory-contents)
    (user-input-error
     "Invalid MEMORY-CONTENTS. The requested MEMORY-CONTENTS should be a JSON object whose keys are ~
      DECLAREd memory names and whose values are a list of pairs where the first element of each ~
      pair is a non-negative integer index into the memory region and the second element is either ~
      an INTEGER or REAL value that should be stored at the corresponding index of the corresponding ~
      memory region."))
  memory-contents)

(defun parse-quil-string (string)
  "Safely parse a Quil string STRING."
  (flet ((no-includes (path)
           (user-input-error
            "Invalid Quil string. INCLUDE is disabled. Refusing to include ~A" path)))
    (let ((cl-quil:*resolve-include-pathname* #'no-includes)
          (cl-quil::*allow-unresolved-applications* t))
      (cl-quil:parse-quil string))))

(defun parse-pauli-noise (noise)
  (unless (and (alexandria:proper-list-p noise)
               (= 3 (length noise))
               (every #'floatp noise))
    (user-input-error "Invalid Pauli noise. Expected a LIST of three FLOATs. Got ~S" noise))
  noise)

(defun parse-sub-request (sub-request)
  (unless (hash-table-p sub-request)
    (user-input-error "Invalid create-job SUB-REQUEST: not a valid JSON object: ~A" sub-request))
  (when (string= "create-job" (gethash "type" sub-request))
    (user-input-error "Invalid create-job SUB-REQUEST type field: ~S."
                      (with-output-to-string (*standard-output*)
                        (yason:encode sub-request))))
  sub-request)
