;;; mdx-dictionary.el --- MDX Dictionary interface for Emacs  -*- lexical-binding: t; -*-

;; Copyright © 2017 DarkSun

;; Author: DarkSun <lujun9972@gmail.com>
;; URL: https://github.com/lujun9972/mdx-dictionary.el
;; Package-Requires: ((popup "0.5.0")(request "0.2.0"))
;; Version: 0.1
;; Keywords: convenience, Chinese, dictionary

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; A simple MDX Dictionary interface for Emacs. It need mdx-server(https://github.com/ninja33/mdx-server) to read MDX/MDD dictionary data
;;
(require 'request)
(require 'shr)
(require 'thingatpt)
(require 'popup)
(require 'subr-x)

(defgroup mdx-dictionary nil
  "dictionary based on mdx-server"
  :prefix "mdx-dictionary-"
  :group 'tools
  :link '(url-link :tag "Github" "https://github.com/lujun9972/mdx-dictionary.el"))

;; (defcustom mdx-dictionary-server-file "/home/lujun9972/github/mdx-dictionary/mdx-server/mdx_server.py"
;;   "mdx-server execution file"
;;   :type 'file)

;;;###autoload
(defcustom mdx-dictionary-server-file (concat (file-name-directory (or load-file-name byte-compile-current-buffer buffer-file-name)) "mdx-server/mdx_server.py")
  "mdx-server execution file"
  :type '(file :must-match t))

(defcustom mdx-dictionary-python "python"
  "python used to start mdx-server"
  :type 'string)

(defcustom mdx-dictionary-server-args nil
  "Args to launch mdx dictionary server"
  :type '(repeat string))

(defvar mdx-dictionary-server-process nil)

(defcustom mdx-dictionary-mdx-file "~/Data/dicts/英英/朗文当代英语辞典第5版/朗文当代英语辞典第5版.mdx"
  "mdx file used as dictionary"
  :type '(file :must-match t))

;;;###autoload
(defun mdx-dictionary-start-server (&optional mdx-file)
  (interactive)
  (mdx-dictionary-stop-server)
  (let ((args `(,@mdx-dictionary-server-args ,(expand-file-name (or mdx-file mdx-dictionary-mdx-file) ))))
    (setq mdx-dictionary-server-process
          (let ((default-directory (file-name-directory (expand-file-name mdx-dictionary-server-file))))
            (make-process :name "mdx-dictionary-server"
                          :buffer "*mdx-dictionary-server*"
                          :command (append (list mdx-dictionary-python
                                                 (file-name-nondirectory mdx-dictionary-server-file))
                                           args)
                          :filter 'mdx-dictionary-process-filter)))))

(defun mdx-dictionary-process-filter (proc string)
  "Accumulates the strings received from the Kagome process."
  (with-current-buffer (process-buffer proc)
    (insert string)))


;;;###autoload
(defun mdx-dictionary-stop-server ()
  (interactive)
  (when (process-live-p mdx-dictionary-server-process )
    (kill-process mdx-dictionary-server-process)
    (setq mdx-dictionary-server-process nil)))

;;;###autoload
(defun mdx-dictionary-request (word)
  "Function used to request `WORD' meanings.

It return an alist looks like
    `((expression . ,expression)
      (us-phonetic . ,us-phonetic)
      (uk-phonetic . ,uk-phonetic)
      (glossary . ,glossary))"
  (let ((word (string-trim word)))
    (let* ((url (format "http://localhost:8000/%s" (url-hexify-string word)))
           (response (request url
                       :sync t
                       :parser (lambda ()
                                 (let ((html (decode-coding-string (buffer-string) 'utf-8)))
                                   (erase-buffer)
                                   (insert html)
                                   (libxml-parse-html-region (point-min) (point-max))))))
           (response-data (request-response-data response)))
      (if response-data
          (funcall (mdx-dictionary-get-parser) word response-data)
        (let ((inhibit-quit t))
          (with-local-quit
            (setq word (read-string "该单词可能是变体,请输入词源(按C-g退出): " word))
            (mdx-dictionary-request word))
          (setq quit-flag nil))))))

(defcustom mdx-dictionary-parsers '(("21世纪大英汉词典.mdx" . mdx-dictionary--21世纪大英汉词典-parser))
  "functions used to parse dom in different mdx files")

(defun mdx-dictionary-get-parser ()
  "return the function used to parse the dom"
  (let* ((mdx-file-name (file-name-nondirectory mdx-dictionary-mdx-file))
         (parser (cdr (assoc mdx-file-name mdx-dictionary-parsers))))
    (or parser 'mdx-dictionary--default-parser)))

(defun mdx-dictionary--default-parser (word dom)
  "Default parser used to parse `DOM'"
  (let ((expression word)
        (glossary (with-temp-buffer
                    (shr-insert-document dom)
                    (buffer-substring-no-properties (point-min) (point-max)))))
    `((expression . ,expression)
      (glossary ,glossary))))

(defun mdx-dictionary--21世纪大英汉词典-parser (word dom)
  "The function used to parser 21世纪大英汉词典"
  (setq q dom)
  (let* ((expression (dom-texts (car (dom-by-class dom "^return-phrase$"))))
         (phonetic (dom-texts (car (dom-by-class dom "^phone$"))))
         (trs-doms (dom-by-class dom "^trs$"))
         (glossary (mapcan (lambda (trs-dom)
                        (let* ((pos-dom (car (dom-by-class trs-dom "^pos$")))
                               (pos (dom-texts pos-dom))
                               (tr-doms (dom-by-class trs-dom "^tr$"))
                               (trs (mapcar (lambda (tr-dom)
                                                  (let ((l-dom (car (dom-by-class tr-dom "l"))))
                                                    (car (last (dom-strings l-dom)))))
                                                tr-doms)))
                          (mapcar (lambda (tr)
                                    (format "%s %s" pos tr))
                                  trs)))
                      trs-doms)))
    `((expression . ,expression)
      (us-phonetic . ,phonetic)
      (glossary . ,glossary))))

(defun mdx-dictionary-query (&optional word)
  (interactive)
  (let* ((word (or word
                   (and (use-region-p) (buffer-substring-no-properties (region-beginning) (region-end)))
                   (word-at-point)))
         (content (mdx-dictionary-request word))
         (expression (cdr (assoc 'expression content)))
         (us-phonetic (cdr (assoc 'us-phonetic content)))
         (uk-phonetic (cdr (assoc 'uk-phonetic content)))
         (glossary (mapconcat #'identity (cdr (assoc 'glossary content)) "\n")))
    (when content
      (popup-tip (format "%s(%s)\n%s"
                         expression
                         (or us-phonetic uk-phonetic "")
                         glossary)))))




(provide 'mdx-dictionary)
;; mdx-dictionary.el ends here
