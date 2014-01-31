;;;; utils.lisp

(defpackage #:glock.order-book
  (:use #:cl #:glock.util #:glock.connection #:st-json)
  (:export #:order-book))

(in-package #:glock.order-book)

(defun make-depth-channel (&optional (output (make-instance 'chanl:channel)))
  (chanl:pexec ()
    (let ((glue (external-program:process-output-stream (external-program:start "node" '("-e" "require('goxstream').createStream({ticker: false, depth: true}).pipe(process.stdout)") :output :stream))))
      (read-line glue)                  ; connected to: wss://websocket.mtgox.com
      (read-line glue)                  ; subscribing to channel: depth.BTCUSD
      (loop (chanl:send output (parse-depth-message (st-json:read-json glue))))))
  output)

(defun parse-depth-message (raw-jso)
  (with-json-slots (type_str price_int volume_int total_volume_int now)
      (getjso "depth" raw-jso)
    (jso "now" (goxstamp (parse-integer now))
         "type" (concatenate 'string type_str "s")
         "price" (/ (parse-integer price_int) (expt 10 5))
         "delta" (/ (parse-integer volume_int) (expt 10 8))
         "total" (/ (parse-integer total_volume_int) (expt 10 8)))))

;;; Talking to the API

(defclass order-book (post-request)
  (:default-initargs :full t))

(defmethod initialize-instance :around ((book order-book) &key full)
  (call-next-method book :path (format nil "money/depth/~:[fetch~;full~]" full)))

(defstruct (order (:constructor %make-order)) price amount time)

(defun make-order (raw-order)
  (with-json-slots (stamp price_int amount_int) raw-order
    (multiple-value-bind (sec nsec) (floor (parse-integer stamp) #.(expt 10 6))
      (%make-order :time (local-time:unix-to-timestamp sec :nsec nsec)
                   :price (/ (parse-integer price_int) #.(expt 10 5))
                   :amount (/ (parse-integer amount_int) #.(expt 10 8))))))

(defmethod request :around ((connection mtgox-connection) (method order-book))
  (with-json-slots (now bids asks) (call-next-method)
    (let ((asks (mapcar #'make-order asks))
          (bids (reduce (lambda (bids order) (cons (make-order order) bids))
                        bids :initial-value nil)))
      (jso "now" now
           "asks" (remove 1/100000000 asks :key #'order-amount)
           "bids" (remove 1/100000000 bids :key #'order-amount)))))

;;; This function is not thread safe!
;;; It intentionally returns (values) to show that the book gets modified
(defun apply-depth-message (depth book)
  (with-json-slots (now type price delta total) depth
    (if (print (/= delta total))
        ;; Modify existing order
        (if (print (zerop total))
            ;; Delete order
            (setf (getjso type book)
                  (remove price (getjso type book) :key #'order-price))
            ;; Adjust order volume
            (let ((order (find price (getjso type book) :key #'order-price)))
              (assert order)
              ;; (assert (local-time:timestamp> now (order-time order)))
              ;; (assert (= total (+ delta (order-amount order))))
              (setf (order-time order) now
                    (order-amount order) total)))
        ;; Add new order
        (let ((test (if (string= type "bids") #'> #'<))
              (new (%make-order :price price :amount total :time now)))
          (if (print (funcall test price (order-price (first (getjso type book)))))
              ;; Add new "best" order
              (push new (getjso type book))
              ;; Add order at appropriate place in list
              (do* ((tail (getjso type book) (cdr tail)))
                   ((or (funcall test price (order-price (car tail)))
                        (null (cdr tail)))
                    (push new (cdr tail))))))))
  (values))
