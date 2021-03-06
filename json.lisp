;;;; JSON parser for LispWorks
;;;;
;;;; Copyright (c) 2012 by Jeffrey Massung
;;;;
;;;; This file is provided to you under the Apache License,
;;;; Version 2.0 (the "License"); you may not use this file
;;;; except in compliance with the License.  You may obtain
;;;; a copy of the License at
;;;;
;;;;    http://www.apache.org/licenses/LICENSE-2.0
;;;;
;;;; Unless required by applicable law or agreed to in writing,
;;;; software distributed under the License is distributed on an
;;;; "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
;;;; KIND, either express or implied.  See the License for the
;;;; specific language governing permissions and limitations
;;;; under the License.
;;;;

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "parsergen"))

(defpackage :json
  (:use :cl :lw :hcl :parsergen :re :lexer)
  (:export
   #:json-decode
   #:json-encode))

(in-package :json)

(deflexer json-lexer
  ("[%s%n]+"                  :next-token)
  ("{"                        :object)
  ("}"                        :end-object)
  ("%["                       :array)
  ("%]"                       :end-array)
  (":"                        :colon)
  (","                        :comma)

  ;; strings use a different lexer
  ("\""                       (push-lexer #'string-lexer :string))

  ;; numbers
  ("[+%-]?%d+%.%d+e[+%-]?%d+" (values :float (parse-float $$)))
  ("[+%-]?%d+%.%d+"           (values :float (parse-float $$)))
  ("[+%-]?%d+e[+%-]?%d+"      (values :int (truncate (parse-float $$))))
  ("[+%-]?%d+"                (values :int (parse-integer $$)))

  ;; identifiers
  ("%a%w*"                    (cond
                               ((string= $$ "true") (values :const :true))
                               ((string= $$ "false") (values :const :false))
                               ((string= $$ "null") (values :const :null))
                               (t
                                (error "Unknown identifier ~s" $$)))))

(deflexer string-lexer
  ("\""                       (pop-lexer :end-string))

  ;; escaped characters
  ("\\n"                      (values :chars #\newline))
  ("\\t"                      (values :chars #\tab))
  ("\\f"                      (values :chars #\formfeed))
  ("\\b"                      (values :chars #\backspace))
  ("\\r"                      (values :chars #\return))

  ;; unicode characters
  ("\\u(%x%x%x%x)"            (let ((n (parse-integer $1 :radix 16)))
                                (values :chars (code-char n))))

  ;; all other characters
  ("\\(.)"                    (values :chars $1))
  ("[^\\\"]+"                 (values :chars $$))

  ;; don't reach the end of file or line
  ("$"                        (error "Unterminated string")))

(defparser json-parser
  ((start value) $1)
  
  ;; single json value
  ((value :const) $1)
  ((value :float) $1)
  ((value :int) $1)
  ((value string) $1)
  ((value array) $1)
  ((value object) $1)

  ;; unparsable values
  ((value :error)
   (error "JSON syntax error"))

  ;; quoted string
  ((string :string chars)
   (reduce #'string-append $2 :initial-value ""))

  ;; character sequences
  ((chars :chars chars) `(,$1 ,@$2))
  ((chars :end-string) `())
 
  ;; objects
  ((object :object :end-object) ())
  ((object :object members) $2)

  ;; members of an object
  ((members string :colon value :comma members)
   `((,$1 ,$3) ,@$5))
  ((members string :colon value :end-object)
   `((,$1 ,$3)))
  
  ;; arrays
  ((array :array elements) (coerce $2 'vector))
  ((array :array :end-array) #())

  ;; elements of an array
  ((elements value :comma elements)
   `(,$1 ,@$3))
  ((elements value :end-array)
   `(,$1)))

(defparser string-parser
  ((start string) $1)

  ;; convert a list of characters to a string
  ((string chars)
   (coerce $1 'lw:text-string))

  ;; collect a list of characters
  ((chars :char chars)
   `(,$1 ,@$2))
  ((chars)
   `()))

(defun json-decode (string &optional source)
  "Convert a JSON string into a Lisp object."
  (let ((tokens (tokenize #'json-lexer string source)))
    (parse #'json-parser tokens)))

(defun json-encode (value)
  "Convert a Lisp object to a JSON string."
  (flet ((encode-object (kv)
           (destructuring-bind (k v)
               kv
             (format nil "~s:~a" k (json-encode v))))
         (encode-char (c)
           (cond
            ((char= c #\newline) "\\n")
            ((char= c #\tab) "\\t")
            ((char= c #\formfeed) "\\f")
            ((char= c #\backspace) "\\b")
            ((char= c #\return) "\\r")
            ((char> c #\~)
             (format nil "\\u~16,'0r" (char-code c)))
            (t
             (string c)))))
    (with-output-to-string (s)
      (cond
       ((listp value)
        (format s "{~{~a~^,~}}" (mapcar #'encode-object value)))
       ((stringp value)
        (format s "\"~{~a~}\"" (map 'list #'encode-char value)))
       ((vectorp value)
        (format s "[~{~a~^,~}]" (map 'list #'json-encode value)))
       ((numberp value)
        (format s "~s" value))
       ((eq value :true)
        (format s "true"))
       ((eq value :false)
        (format s "false"))
       ((eq value :null)
        (format s "null"))
       (t
        (error "Cannot encode value as JSON: ~a" value))))))

