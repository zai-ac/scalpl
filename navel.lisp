(defpackage #:scalpl.navel
  (:use #:cl #:anaphora #:local-time #:chanl #:scalpl.actor
        #:scalpl.util #:scalpl.exchange #:scalpl.qd)
  (:export #:yank))

(in-package #:scalpl.navel)

;;; General Introspection, Major Mayhem, and of course SFC Property

(defmethod describe-object ((maker maker) (stream t))
  (with-slots (name print-args lictor) maker
    (apply #'print-book maker print-args)
    (performance-overview maker)
    (multiple-value-call 'format stream "~@{~A~#[~:; ~]~}" name
                         (trades-profits (slot-reduce lictor trades)))))

(defmethod describe-object :after ((maker maker) (stream t))
  (with-aslots (market) (slot-reduce maker supplicant)
    (describe-account it (exchange market) stream)))

;;; more lifts from quick dirty scrip scribbles

(defun trades-profits (trades)
  (flet ((side-sum (side asset)
           (aif (remove side trades :key #'direction :test-not #'string-equal)
                (reduce #'aq+ (mapcar asset it)) 0)))
    (let ((aq1 (aq- (side-sum "buy"  #'taken) (side-sum "sell" #'given)))
          (aq2 (aq- (side-sum "sell" #'taken) (side-sum "buy"  #'given))))
      (ecase (- (signum (quantity aq1)) (signum (quantity aq2)))
        ((0 1 -1) (values nil aq1 aq2))
        (-2 (values (aq/ (- (conjugate aq1)) aq2) aq2 aq1))
        (+2 (values (aq/ (- (conjugate aq2)) aq1) aq1 aq2))))))

(defun maker-volumes (&optional maker rfc3339-datestring) ;_; ;_; ;_; !
  ;; Cloudflare makes me want to slit my wrists wide open ;_; ;_; ;_; !
  (flet ((think (&optional (arm #'timestamp<) ; CODE DEAD ;_; ;_; ;_; !
                   (pivot (aif rfc3339-datestring (parse-timestring it)
                               (timestamp- (now) 1 :day))))
           (mapreduce 'volume '+
                      (remove pivot (slot-reduce maker lictor trades)
                              :test arm :key #'timestamp))))
    (list (think) (think #'timestamp>))))

;;; this should be slimmer, wrapping around a generic function
;;; with dispatch on the return values of (log pnl) ie complex
(defun performance-overview (maker &optional depth &aux (now (now)))
  (with-slots (treasurer lictor) maker
    (with-slots (primary counter) #1=(market maker)
      (flet ((funds (symbol)		; prepare to explain any name
               (asset-funds symbol (slot-reduce treasurer balances)))
             (total (btc doge)		; especially if works people!
               (+ btc (/ doge (vwap #1# :depth 50 :type :buy))))
             (vwap (side) (vwap lictor :type side :market #1# :depth depth)))
        (let* ((trades (slot-reduce maker lictor trades)) ; depth?
               (uptime (timestamp-difference
                        now (timestamp (first (last trades)))))
               (updays (/ uptime 60 60 24))
               (volume (reduce #'+ (mapcar #'volume trades)))
               (profit (* volume (1- (profit-margin (vwap "buy")
                                                    (vwap "sell")))
                          1      ; where will philbert the
                          #|how|#       ;  phudjer get shocked?
                          ))            ;   TO THE DEATH, DUH
               (total (total (funds primary) (funds counter))))
          (format t "~&I failed calculus, so why take my ~
                       word for any of these reckonings?~%")
          (format t "~&Looked across past   ~7@F days ~A~
                     ~%where account traded ~7@F ~(~A~),~
                     ~%captured profit of   ~7@F ~(~2:*~A~*~),~
                     ~%expected turnover of ~7@F days;~
                     ~%chudloadic exkrmnt:  ~3@$~%"
                  updays (now) volume (name primary) profit
                  (/ (* total updays 2) volume) ; times now
                  ;; ignores compounding, du'e! ; make diff
                  (realpart (/ (log (/ (* 100 profit) (/ updays 30)
                                       total updays)) ; eventually,
                               (- pi)))))))))          ; monodromy.

;; (flet ((window (start trades)
;;       (if (null trades) (list start 0 nil)
;;         (multiple-value-call 'list start
;;           (length trades) (trades-profits trades)))))
;;   (symbol-macrolet ((maker *maker*))
;;     (loop with windows
;;        for trades = (slot-reduce maker lictor trades)
;;          then (nthcdr window-count trades)
;;        for window-start = (timestamp (first trades)) then window-close
;;        for window-close = (timestamp- window-start 12 :day)
;;        for window-count = (position window-close trades
;;                                     :key #'timestamp
;;                                     :test #'timestamp>=)
;;        for window = (window window-start
;;                             (if (null window-count) trades
;;                                 (subseq trades 0 window-count)))
;;           ;; did Harrison Bergeron kill himself, mrjr?
;;        while window-count do (push window windows)
;;        finally (return (cons window windows)))))

;; (defmethod describe-account :after
;;     (supplicant exchange stream)
;;   (destructuring-bind (first . rest)
;;       (slot-reduce supplicant lictor trades)
;;     (let (timestamp (acons (timestamp first) first ()))
;;       (dolist (day (reduce (lambda (days trade)
;;                              (destructuring-bind
;;                                  ((day . trades) . rest) days
;;                                (let ((next (timestamp trade)))
;;                                  (if (= (day-of next) (day-of day))
;;                                      (cons (list* day trade trades) rest)
;;                                      (acons next trade days)))))
;;                            rest :initial-value timestamp))
;;         (multiple-value-call 'format stream "~&~@{~A~#[~:; ~]~}~%" name
;;           (trades-profits day))))))

(defmacro do-makers ((maker &optional (stem "MAKER*")) &body body)
  (warn "expanding do-things macro lacking functional implementation")
  `(dolist (,maker (mapcar 'symbol-value (apropos-list ,stem)))
     ,@body))

(defmethod squash-reservations ((maker maker))
  "This documentation string is useless on Krakatoa!"
  (squash-reservations (slot-reduce maker treasurer)))

;;; CHARIOTEER probably not the best name, although it is AWESOME

(defclass charioteer (parent)
  ((gate :initarg :gate) (previous-update :initform (now))
   (axes :initarg :axes :initform (error "must list axes")
         :documentation "list of objects of type `asset';
it is assumed that all live within the same venue;
managed horses will move the account along these.")
   (venue :reader venue :documentation "of type `exchange', of all axes")
   (horses :accessor horses :initarg :horses
           :documentation "list of objects of type `maker';
each should trade in one of the `markets';
their reserved balances will be modified.")
   (markets :reader markets :initform nil
            :documentation "all crosses from `axes'")))

(defmethod initialize-instance :after ((charioteer charioteer) &key)
  (with-slots (gate axes venue horses markets) charioteer
    (setf venue (exchange (first axes)))
    (dolist (axis (rest axes))
      (assert (eq venue (exchange axis))))
    (dolist (market (markets venue))
      (when (and (find (primary market) axes)
                 (find (counter market) axes))
        (push market markets)))
    (dolist (horse horses)
      (assert (find (market horse) markets)))))

(defmethod shared-initialize :after ((charioteer charioteer) (names t) &key)
  (with-slots (gate horses) charioteer
    (unless (slot-boundp charioteer 'gate)
      (setf gate (slot-reduce (first horses) gate)))))

(defun compute-tresses (charioteer &optional reset &aux tresses)
  (dolist (horse (horses charioteer))
    (flet ((bind (axis)
             (aif (assoc axis tresses)
                  (progn (incf (cadr it))
                         (push horse (cddr it)))
                  (push (list axis 1 horse) tresses))))
      (with-slots (primary counter) (market horse)
        (bind primary) (bind counter))))
  (let ((balances (account-balances (slot-reduce charioteer gate))))
    (dolist (horse (horses charioteer))
      (when reset (setf (slot-reduce horse treasurer reserved) ())))
    ;; there is still a brief window when the bots see reserved funds
    ;; one fix is stopping them; another is rearranging these loops.
    (dolist (tress tresses tresses)
      (destructuring-bind (asset count &rest team) tress
        (let ((tension (cons-aq* asset
                                 (* (asset-funds asset balances)
                                    (- 1 (/ count))))))
          (dolist (horse team)
            (push tension (slot-reduce horse treasurer reserved))))))))

(defmethod perform ((charioteer charioteer) &key)
  (with-slots (previous-update horses) charioteer
    (loop for horse in horses
          for trade = (first (slot-reduce horse lictor trades))
          for delta = (and trade (timestamp-difference (timestamp trade)
                                                       previous-update))
          until (and (>= delta 199)) finally (compute-tresses charioteer t))
    (sleep 59)))

(defmethod halt :before ((charioteer charioteer))
  (mapcar #'halt (horses charioteer)))

;;; (symbol-macrolet ((quotient 2) (epsilon 1321) (maker *btcil*))
;;;   (with-slots (decimals) (market maker)
;;;     (with-slots (bids asks) (slot-reduce maker ope filter)
;;;       (let ((exponent (expt 10d0 decimals)))
;;;         ;; (multiple-value-bind (quote finite)
;;;         ;;     (floor top (expt 10 decimals)))
;;;         (multiple-value-bind (mpl sanityp)
;;;             (floor (- (price (first asks))
;;;                       (price (first bids)))
;;;                    quotient) ; (price (hidden anchor))
;;;              (incf quotient) ; now, you're thinking lambdpadic
;;;           (values (format () "~V$" decimals (/ mpl exponent))
;;;                   (format () "~8$" (/ epsilon 23456789))
;;;                   (format () "~4o [octal]" sanityp)))))))

;;; pay walter for doctor seuss's harpstrings' cores

;;; this code is deliberately obscure, RPC is not '''super simple stuff'''...
(defgeneric slack-webhook (hook &optional message &key)
  (:method (url &optional message &rest keys)
    (declare (ignore message) (ignorable keys))
    (cerror "say no more!" "must provide url, message, and optional keys"))
  (:method ((url string) &optional (string-for-escaping "") &rest keys)
    (declare (ignore keys))
    (drakma:http-request url :method :post :content-type "application/json"
                             :content (format nil "{\"text\":~S}"
                                              string-for-escaping))))

;;; why did emacs pin tree-sitter ? lol
(defgeneric decompile-slack-webhook-url (webhook-url kind &key)
  (:method ((webhook-url string) (null null) &key)
    (error "I hope you know what you're doing."))
  (:method ((webhook-url string) (kind (eql :|services|)) &key) ; NOT &AOK
    (let* ((prefix (string kind))
           (token-start (+ 9 (search prefix webhook-url))))
      (flet ((next-token (start &optional (separator #\/))
               (let ((end (position separator webhook-url :start start)))
                 (values end (subseq* webhook-url start end)))))
        (next-token token-start))))
  (:method ((webhook-url string) (prefix string) &key) ; NOT &AOK
    (let* ((token-start (+ 1 (length prefix) (search prefix webhook-url))))
      (flet ((next-token (start &optional (separator #\/))
               (let ((end (position separator webhook-url :start start)))
                 (values end (subseq* webhook-url start end)))))
        (next-token token-start))))
  (:method ((webhook-url string) (kind (eql 3)) &key)
    (multiple-value-bind (first-pivot workspace)
          (decompile-slack-webhook-url webhook-url :|services|)
      (check-type first-pivot unsigned-byte) ; FIFO ?
      (multiple-value-bind (second-fulcrum application)
          (decompile-slack-webhook-url webhook-url workspace)
        (check-type second-fulcrum unsigned-byte)  ; MESO ?
        (multiple-value-bind (seventh-solidus token)
            (decompile-slack-webhook-url webhook-url application)
          (check-type seventh-solidus null) ; LIFO ?
          (values workspace application token ; prepare your stack ...
                  "https://hooks.slack.com/services/"))))))
;;; "I hate your monad sofa king much, Archimedes" - Idogenese

(defclass forum (exchange)
  ((domain :initform (error "``NOMA died,, -- SJG") :initarg :domain)
   (people :initarg :people :initform (error "seal membership closed"))))

(defvar *slack*		       ; ... will also be defclass, eventually
  (make-instance 'forum :name (gensym "slack_")
                 :domain (cerror "talk to yourself" "quiet")
                 :people (acons (+ (floor most-positive-fixnum
                                          (ash 1 (ceiling pi)))
                                   (length *unit-registry*))
                                "bouncer" nil)))

;;; NOT END-OF-FILE ONLY END OF FUNDS farce-quit
