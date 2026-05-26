Here’s a clean, scalable **Common Lisp project structure** for a **text-based game** (interactive fiction / roguelike / choice game). It’s set up like a real app: systems, packages, modules, data, tests, and a place for your DSL/macros if you want them.

## Recommended project layout

```
textquest/
  README.md
  LICENSE
  .gitignore

  textquest.asd
  textquest-tests.asd

  src/
    packages.lisp            ; all defpackage in one place
    main.lisp                ; entrypoint (main function)
    cli.lisp                 ; REPL/terminal loop, command reading

    core/
      util.lisp              ; helpers: strings, random, tables
      errors.lisp            ; conditions/restarts
      time.lisp              ; optional: turns, scheduling
      log.lisp               ; optional: debug logging

    game/
      state.lisp             ; world-state struct, player struct, inventory
      world.lisp             ; rooms/nodes graph + loading
      rules.lisp             ; rule engine: validations, triggers
      actions.lisp           ; verbs: look, go, take, use, talk
      combat.lisp            ; optional
      dialogue.lisp          ; optional branching dialogue
      quests.lisp            ; optional quest flags / progress

    content/
      data.lisp              ; built-in content (rooms/items) in Lisp
      parser.lisp            ; parse content files (json/yaml optional later)
      scripts.lisp           ; story scripts / event hooks

    dsl/
      dsl-packages.lisp      ; DSL package(s)
      macros.lisp            ; defroom/defitem/defnpc etc.
      compile.lisp           ; expand DSL into world objects

    io/
      save.lisp              ; save/load (s-expr) to disk
      settings.lisp          ; keybinds, options
      render.lisp            ; text formatting, color (optional)

    ai/
      npc.lisp               ; optional: NPC behaviors
      planner.lisp           ; optional: goal/utility planner

  assets/
    worlds/
      demo.world.lisp        ; content via DSL or plain data
    saves/
      .keep

  test/
    core-test.lisp
    parser-test.lisp
    actions-test.lisp
    world-test.lisp

  scripts/
    run.lisp                 ; quick runner for SBCL/CLISP
    repl.lisp                ; dev helper to load & jump into game
```

Why this works:
- `core/` = boring reusable primitives  
- `game/` = *engine logic* (state, rules, actions)  
- `content/` + `assets/` = your story/world data  
- `dsl/` = macros so you can author content in a nice declarative way  
- `io/` = saving + rendering concerns separated  
- tests are isolated and can load the system without running the game loop

---

## Minimal `textquest.asd` (system definition)

```lisp
(asdf:defsystem "textquest"
  :version "0.1.0"
  :serial t
  :components
  ((:file "src/packages")
   (:file "src/core/util")
   (:file "src/core/errors")

   (:file "src/game/state")
   (:file "src/game/world")
   (:file "src/game/rules")
   (:file "src/game/actions")

   (:file "src/io/render")
   (:file "src/io/save")

   (:file "src/content/data")
   (:file "src/cli")
   (:file "src/main")))
```

(You can switch to non-serial and add `:depends-on` later.)

---

## Packages layout (`src/packages.lisp`)

Keep packages centralized so compile/load order stays sane.

```lisp
(defpackage #:textquest.core
  (:use #:cl)
  (:export #:trim #:split-words #:kw #:ensure-list))

(defpackage #:textquest.game
  (:use #:cl #:textquest.core)
  (:export
    #:*game* #:make-game #:game-player #:game-world
    #:do-action #:available-actions
    #:look #:go #:take #:use))

(defpackage #:textquest.io
  (:use #:cl #:textquest.core #:textquest.game)
  (:export #:render #:prompt #:save-game #:load-game))

(defpackage #:textquest.dsl
  (:use #:cl #:textquest.core #:textquest.game)
  (:export #:defroom #:defitem #:defnpc #:connect))

(defpackage #:textquest
  (:use #:cl #:textquest.core #:textquest.game #:textquest.io #:textquest.dsl)
  (:export #:main))
```

---

## File responsibilities (quick map)

### `src/game/state.lisp`
- `defstruct game`, `defstruct player`, inventory, flags
- “single source of truth” for state shape

### `src/game/world.lisp`
- rooms graph, lookups, current room, exits

### `src/game/actions.lisp`
- commands as functions: `look`, `go`, `take`, `use`
- a dispatch function `do-action` that takes parsed tokens

### `src/cli.lisp`
- reads a line, tokenizes, calls `do-action`, prints result

### `src/dsl/macros.lisp`
- authoring macros that expand into world-state registration

---

## Optional: “Engine vs Content” separation

If you want to ship multiple games later, split into two systems:

```
textquest-engine/
textquest-demo/   ; depends-on engine
```

That’s a very “real” architecture.

---

## A tiny DSL folder approach (so content feels nice)

Example goal: write this:

```lisp
(defroom tavern
  :title "The Rusty Byte"
  :desc  "Warm light. Loud laughter."
  :exits (north alley))

(defroom alley
  :title "Alley"
  :desc  "Cold. Wet stone."
  :exits (south tavern))
```

…and have it register rooms into the world automatically.

That’s exactly why `dsl/` exists.

---

If you want, I can also drop a **fully working skeleton** (minimal files filled in: `main`, `cli`, `state`, `world`, `actions`, and a `defroom` DSL) so you can run:

- `sbcl --load scripts/run.lisp`
- and immediately play a 3-room game.

Got you — add a **deductive retriever** as its own module: it stores facts, applies rules to **derive new facts**, and can **retrieve** the most relevant facts for a query (room description, NPC knowledge, quest state, etc.).

Below is a practical way to bolt it onto the project structure I gave you.

## 1) Project structure update

Add a `reasoning/` module:

```
src/
  reasoning/
    kb.lisp          ; knowledge base: facts, indexes
    rules.lisp       ; rule representation + forward chaining
    retrieve.lisp    ; query + scoring/relevance retrieval
```

Update `packages.lisp` with a new package:

```lisp
(defpackage #:textquest.reasoning
  (:use #:cl #:textquest.core)
  (:export
    #:make-kb #:kb-assert! #:kb-retract! #:kb-query
    #:define-rule #:kb-run!
    #:retrieve))
```

And add to `textquest.asd` before game/actions (so game can call it):

```lisp
(:file "src/reasoning/kb")
(:file "src/reasoning/rules")
(:file "src/reasoning/retrieve")
```

---

## 2) Knowledge base (facts + simple indexing) — `src/reasoning/kb.lisp`

Facts are S-expressions like:

- `(at player tavern)`
- `(connected tavern north alley)`
- `(has-key player brass-key)`
- `(locked alley-door)`

```lisp
(in-package #:textquest.reasoning)

(defstruct (kb (:constructor make-kb ()))
  ;; facts stored as canonical s-exprs
  (facts (make-hash-table :test #'equal))
  ;; index: predicate symbol -> list of facts
  (by-pred (make-hash-table :test #'eq))
  ;; optional: entity symbol -> list of facts (fast retrieval)
  (by-entity (make-hash-table :test #'eq)))

(defun %index-add (kb fact)
  (let ((pred (first fact)))
    (push fact (gethash pred (kb-by-pred kb)))
    (dolist (x (rest fact))
      (when (symbolp x)
        (push fact (gethash x (kb-by-entity kb)))))))

(defun %index-remove (kb fact)
  (let ((pred (first fact)))
    (setf (gethash pred (kb-by-pred kb))
          (remove fact (gethash pred (kb-by-pred kb)) :test #'equal))
    (dolist (x (rest fact))
      (when (symbolp x)
        (setf (gethash x (kb-by-entity kb))
              (remove fact (gethash x (kb-by-entity kb)) :test #'equal))))))

(defun kb-assert! (kb fact)
  "Add FACT if not already present."
  (unless (gethash fact (kb-facts kb))
    (setf (gethash fact (kb-facts kb)) t)
    (%index-add kb fact))
  fact)

(defun kb-retract! (kb fact)
  (when (gethash fact (kb-facts kb))
    (remhash fact (kb-facts kb))
    (%index-remove kb fact))
  fact)

(defun kb-all-facts (kb)
  (loop for k being the hash-keys of (kb-facts kb) collect k))

(defun kb-facts-by-pred (kb pred)
  (copy-list (gethash pred (kb-by-pred kb))))

(defun kb-facts-by-entity (kb ent)
  (copy-list (gethash ent (kb-by-entity kb))))
```

---

## 3) Deduction engine (forward chaining) — `src/reasoning/rules.lisp`

Simple rule form:

- **IF** patterns match, **THEN** assert new facts.

Example rule:
- IF `(at player ?room)` and `(has-key player brass-key)` THEN `(can-open player ?room locked-door)`

```lisp
(in-package #:textquest.reasoning)

(defstruct rule
  name
  if        ; list of patterns
  then      ; list of templates
  (priority 0))

(defparameter *rules* nil)

(defun define-rule (name if then &key (priority 0))
  (push (make-rule :name name :if if :then then :priority priority) *rules*)
  name)

(defun var-p (x)
  (and (symbolp x)
       (> (length (symbol-name x)) 0)
       (char= (char (symbol-name x) 0) #\?)))

(defun subst-vars (expr env)
  (cond
    ((var-p expr) (or (cdr (assoc expr env :test #'eq)) expr))
    ((consp expr) (cons (subst-vars (car expr) env)
                        (subst-vars (cdr expr) env)))
    (t expr)))

(defun unify (pattern fact &optional env)
  "Unify PATTERN with FACT. Returns extended env or NIL."
  (cond
    ((null env) (setf env '()))
    (t env))
  (labels ((u (p f env0)
             (cond
               ((var-p p)
                (let ((hit (assoc p env0 :test #'eq)))
                  (cond (hit (if (equal (cdr hit) f) env0 nil))
                        (t (acons p f env0)))))
               ((and (consp p) (consp f))
                (let ((env1 (u (car p) (car f) env0)))
                  (and env1 (u (cdr p) (cdr f) env1))))
               (t (if (equal p f) env0 nil)))))
    (u pattern fact env)))

(defun match-all (kb patterns)
  "Return list of envs satisfying all PATTERNS."
  (labels ((step (pats envs)
             (if (endp pats)
                 envs
                 (let* ((pat (first pats))
                        (pred (first pat))
                        (cands (if (symbolp pred)
                                   (kb-facts-by-pred kb pred)
                                   (kb-all-facts kb)))
                        (next-envs '()))
                   (dolist (env envs)
                     (dolist (f cands)
                       (let ((env2 (unify pat f env)))
                         (when env2 (push env2 next-envs)))))
                   (step (rest pats) next-envs)))))
    (step patterns (list '()))))

(defun kb-run! (kb &key (max-steps 500))
  "Forward-chain rules until fixpoint or max steps."
  (let ((steps 0)
        (added 0))
    (loop
      (when (>= steps max-steps) (return (values added :max-steps)))
      (incf steps)
      (let ((any nil))
        (dolist (r (sort (copy-list *rules*) #'> :key #'rule-priority))
          (dolist (env (match-all kb (rule-if r)))
            (dolist (tmpl (rule-then r))
              (let ((fact (subst-vars tmpl env)))
                (unless (gethash fact (kb-facts kb))
                  (kb-assert! kb fact)
                  (incf added)
                  (setf any t)))))))
        (unless any (return (values added :fixpoint))))))

(defun kb-query (kb pattern)
  "Return env bindings that satisfy PATTERN."
  (let* ((pred (first pattern))
         (cands (kb-facts-by-pred kb pred))
         (out '()))
    (dolist (f cands (nreverse out))
      (let ((env (unify pattern f '())))
        (when env (push env out))))))
```

---

## 4) Retriever (relevance-based fact retrieval) — `src/reasoning/retrieve.lisp`

This is the “retriever” part: given a query (usually symbols like player + room + current action), return the most relevant facts.

```lisp
(in-package #:textquest.reasoning)

(defun score-fact (fact focus)
  "Simple scoring:
   +3 if shares predicate
   +2 for each shared entity symbol
   +1 if shares any symbol at all"
  (let ((s 0))
    (when (member (first fact) focus :test #'eq) (incf s 3))
    (dolist (x (rest fact))
      (when (and (symbolp x) (member x focus :test #'eq))
        (incf s 2)))
    (when (some (lambda (x) (and (symbolp x) (member x focus :test #'eq)))
                fact)
      (incf s 1))
    s))

(defun retrieve (kb focus &key (limit 15))
  "FOCUS is a list of symbols, e.g. '(player tavern look locked)'.
   Returns top facts by score."
  (let ((cands '()))
    ;; pull candidates via entity index first (fast)
    (dolist (f focus)
      (when (symbolp f)
        (setf cands (nconc cands (kb-facts-by-entity kb f)))))
    ;; fallback: if nothing, use everything
    (when (null cands)
      (setf cands (kb-all-facts kb)))
    ;; unique + score
    (let* ((uniq (remove-duplicates cands :test #'equal))
           (scored (mapcar (lambda (fact) (cons (score-fact fact focus) fact)) uniq))
           (sorted (sort scored #'> :key #'car)))
      (mapcar #'cdr (subseq sorted 0 (min limit (length sorted)))))))
```

---

## 5) How the game uses it

In `src/game/state.lisp`, add a KB to the game:

```lisp
;; inside your game struct
;; (kb (textquest.reasoning:make-kb))
```

Then whenever state changes, assert base facts:

- player location
- inventory
- room connections
- locks, flags

Run deduction after important changes:

```lisp
(textquest.reasoning:kb-run! (game-kb *game*))
```

And for command handling, retrieve facts relevant to the moment:

```lisp
(let* ((kb (game-kb *game*))
       (room (player-room (game-player *game*)))
       (facts (textquest.reasoning:retrieve kb (list 'player room 'look))))
  ;; use FACTS to decide what to describe / allow
  facts)
```

---

## 6) Example rules you’ll actually want

```lisp
;; if connected, then can-go
(textquest.reasoning:define-rule
 'can-go
 '((connected ?from ?dir ?to)
   (at player ?from))
 '((can-go player ?dir ?to)))

;; if locked and no key, block
(textquest.reasoning:define-rule
 'blocked-by-lock
 '((locked ?door)
   (wants-open player ?door)
   (not-has-key player ?key)) ; you can model negation as explicit facts
 '((blocked player ?door locked)))
```

Common Lisp doesn’t have built-in negation-as-failure here; simplest is:
- maintain explicit negative facts like `(not-has-key player brass-key)` when appropriate, or
- implement a `not` pattern operator (I can add that if you want).

---

If you tell me which deduction style you want:
- **Forward chaining** (what I gave) — great for games
- **Backward chaining** (Prolog-ish “prove goals”)
- **Hybrid** (forward for derived world facts, backward for “can I do X?”)

…I’ll tailor the rule syntax and add `not`, `or`, and priorities so it feels like a real game-logic DSL.

Yep — you’re basically asking for a **classic AI architecture** inside your text game:

- **Production system** (rule engine: IF conditions THEN actions)
- **Slots + fillers** (frame/semantic-network style knowledge)
- **Filler database** (indexing + retrieval of fillers, like “all things that fill slot X”, “all facts about entity Y”)

Below is a clean way to add all three, and make them play nicely with your existing game modules.

---

## 1) Project structure additions

```
src/
  reasoning/
    kb.lisp                 ; base fact store (optional, keep it)
    retrieve.lisp           ; relevance retrieval (optional)

    frames.lisp             ; slot/filler DB (frames + indexing)
    productions.lisp        ; production system (match/fire cycle)
    wm.lisp                 ; working memory glue (facts + frames)
```

Update `packages.lisp`:

```lisp
(defpackage #:textquest.reasoning
  (:use #:cl #:textquest.core)
  (:export
    ;; Frames / slots / fillers
    #:make-fdb #:fdb-assert! #:fdb-retract! #:fdb-get #:fdb-values
    #:fdb-entities-with #:fdb-all-slots #:fdb-all-facts

    ;; Productions
    #:defprod #:run-productions! #:*productions* #:*trace-productions*

    ;; WM helpers
    #:wm-focus #:wm-set-focus!))
```

---

## 2) Slot + filler database (Frames) — `src/reasoning/frames.lisp`

Representation:
- A “fact” is **(entity slot filler)**, e.g. `(tavern :desc "Warm light")`
- Internally, store:
  - `E→(slot→fillers)`
  - `slot→(filler→entities)` index (fast “who has this filler?”)
  - `slot→entities` index (fast “who has slot?”)

```lisp
(in-package #:textquest.reasoning)

(defstruct (fdb (:constructor make-fdb ()))
  (e->slots (make-hash-table :test #'eq))          ; entity -> hash(slot -> list fillers)
  (slot->ents (make-hash-table :test #'eq))        ; slot -> list entities
  (slot+filler->ents (make-hash-table :test #'equal))) ; (slot filler) -> list entities

(defun %slotmap (db ent)
  (or (gethash ent (fdb-e->slots db))
      (setf (gethash ent (fdb-e->slots db))
            (make-hash-table :test #'eq))))

(defun %get-fillers (slotmap slot)
  (copy-list (gethash slot slotmap)))

(defun %push-uniq (x place &key (test #'equal))
  (unless (member x (symbol-value place) :test test)
    (set place (cons x (symbol-value place)))))

(defun %push-uniq* (x lst &key (test #'equal))
  (if (member x lst :test test) lst (cons x lst)))

(defun fdb-assert! (db ent slot filler)
  "Assert (ent slot filler)."
  (let* ((slotmap (%slotmap db ent))
         (old (%get-fillers slotmap slot)))
    (unless (member filler old :test #'equal)
      (setf (gethash slot slotmap) (cons filler old))
      ;; index slot->ents
      (setf (gethash slot (fdb-slot->ents db))
            (%push-uniq* ent (gethash slot (fdb-slot->ents db)) :test #'eq))
      ;; index (slot filler)->ents
      (let ((k (list slot filler)))
        (setf (gethash k (fdb-slot+filler->ents db))
              (%push-uniq* ent (gethash k (fdb-slot+filler->ents db)) :test #'eq))))
    (list ent slot filler)))

(defun fdb-retract! (db ent slot filler)
  "Retract (ent slot filler) if present."
  (let* ((slotmap (gethash ent (fdb-e->slots db))))
    (when slotmap
      (let ((fillers (gethash slot slotmap)))
        (when (member filler fillers :test #'equal)
          (setf (gethash slot slotmap) (remove filler fillers :test #'equal))
          ;; NOTE: indexes are left conservative (could be cleaned lazily)
          (list ent slot filler))))))

(defun fdb-get (db ent slot &optional default)
  "Return first filler for (ent slot), or DEFAULT."
  (let* ((slotmap (gethash ent (fdb-e->slots db))))
    (if (null slotmap) default
        (let ((fillers (gethash slot slotmap)))
          (if fillers (first fillers) default)))))

(defun fdb-values (db ent slot)
  "Return all fillers for (ent slot)."
  (let ((slotmap (gethash ent (fdb-e->slots db))))
    (if slotmap (copy-list (gethash slot slotmap)) '())))

(defun fdb-entities-with (db slot filler)
  "Who has (slot filler)?"
  (copy-list (gethash (list slot filler) (fdb-slot+filler->ents db))))

(defun fdb-all-slots (db ent)
  (let ((slotmap (gethash ent (fdb-e->slots db))))
    (if (null slotmap) '()
        (loop for k being the hash-keys of slotmap collect k))))

(defun fdb-all-facts (db)
  "Return all (ent slot filler) triples."
  (let ((out '()))
    (maphash
     (lambda (ent slotmap)
       (maphash
        (lambda (slot fillers)
          (dolist (f fillers)
            (push (list ent slot f) out)))
        slotmap))
     (fdb-e->slots db))
    (nreverse out)))
```

### How you’ll use it for game content
```lisp
;; Rooms as frames
(fdb-assert! db 'tavern :title "The Rusty Byte")
(fdb-assert! db 'tavern :desc  "Warm light. Loud laughter.")
(fdb-assert! db 'tavern :exit  '(north alley))
```

This makes “room description retrieval” trivial via slots.

---

## 3) Production system (match–select–act) — `src/reasoning/productions.lisp`

We’ll implement an OPS-ish core:

- Working memory is **triples** from the FDB (and optionally plain facts).
- A production has:
  - `:if` patterns (triple patterns with variables)
  - `:when` optional predicate on bindings
  - `:then` actions (assert/retract/side-effect)
  - `:salience` priority
- Run cycle:
  1) build conflict set (all matches)
  2) pick best (highest salience)
  3) fire (apply actions)
  4) repeat until no more or max steps

### Pattern format
A pattern is `(ent slot filler)` where any can be a variable symbol like `?x`.

```lisp
(in-package #:textquest.reasoning)

(defstruct production
  name if when then (salience 0))

(defparameter *productions* '())
(defparameter *trace-productions* nil)

(defun var-p (x)
  (and (symbolp x)
       (let ((n (symbol-name x)))
         (and (> (length n) 0) (char= (char n 0) #\?)))))

(defun bind (var val env)
  (let ((hit (assoc var env :test #'eq)))
    (cond (hit (and (equal (cdr hit) val) env))
          (t (acons var val env)))))

(defun unify-atom (p f env)
  (cond
    ((var-p p) (bind p f env))
    (t (and (equal p f) env))))

(defun unify-triple (pat triple env)
  (destructuring-bind (pe ps pf) pat
    (destructuring-bind (e s f) triple
      (let ((env1 (unify-atom pe e env)))
        (and env1
             (let ((env2 (unify-atom ps s env1)))
               (and env2 (unify-atom pf f env2))))))))

(defun subst-vars (x env)
  (cond
    ((var-p x) (or (cdr (assoc x env :test #'eq)) x))
    ((consp x) (mapcar (lambda (y) (subst-vars y env)) x))
    (t x)))

(defmacro defprod (name (&key (salience 0)) if &optional when then)
  `(push (make-production :name ',name
                          :if ',if
                          :when ,when
                          :then ',then
                          :salience ,salience)
         *productions*))

(defun %matches (db prod)
  "Return list of env bindings that satisfy all IF triple patterns."
  (labels ((step (patterns envs)
             (if (endp patterns)
                 envs
                 (let ((pat (first patterns))
                       (next '()))
                   (dolist (env envs)
                     (dolist (tr (fdb-all-facts db))
                       (let ((env2 (unify-triple pat tr env)))
                         (when env2 (push env2 next)))))
                   (step (rest patterns) next)))))
    (let ((envs (step (production-if prod) (list '()))))
      (if (production-when prod)
          (remove-if-not (lambda (env) (funcall (production-when prod) env)) envs)
          envs))))

(defun %apply-action (db action env)
  "Actions are:
   (:assert ent slot filler)
   (:retract ent slot filler)
   (:call fn arg1 arg2 ...)"
  (ecase (first action)
    (:assert
     (destructuring-bind (_ ent slot filler) action
       (declare (ignore _))
       (fdb-assert! db (subst-vars ent env) (subst-vars slot env) (subst-vars filler env))))
    (:retract
     (destructuring-bind (_ ent slot filler) action
       (declare (ignore _))
       (fdb-retract! db (subst-vars ent env) (subst-vars slot env) (subst-vars filler env))))
    (:call
     (destructuring-bind (_ fn &rest args) action
       (declare (ignore _))
       (apply fn (mapcar (lambda (a) (subst-vars a env)) args))))))

(defun run-productions! (db &key (max-steps 200))
  "Fire productions until quiescence or max-steps. Returns fired count."
  (let ((fired 0))
    (loop for step from 1 to max-steps do
      (let ((conflicts '()))
        (dolist (p *productions*)
          (dolist (env (%matches db p))
            (push (list (production-salience p) p env) conflicts)))
        (when (null conflicts) (return fired))
        (setf conflicts (sort conflicts #'> :key #'first))
        (destructuring-bind (sal p env) (first conflicts)
          (declare (ignore sal))
          (when *trace-productions*
            (format t "~&[PROD] ~A  env=~S~%" (production-name p) env))
          (dolist (act (production-then p))
            (%apply-action db act env))
          (incf fired))))
    fired))
```

That’s a real production loop you can extend with:
- refraction (don’t fire same prod with same bindings twice)
- agenda groups
- stochastic conflict resolution, etc.

---

## 4) Working memory glue — `src/reasoning/wm.lisp`

This is the bridge between the **game state** and the **frame DB** + **productions**.

```lisp
(in-package #:textquest.reasoning)

(defstruct (wm (:constructor make-wm ()))
  (db (make-fdb))
  (focus '())) ; list of symbols currently “salient”

(defun wm-focus (wm) (wm-focus wm))
(defun wm-set-focus! (wm focus) (setf (wm-focus wm) focus))
```

In your `game/state.lisp`, your game can hold a `wm`:

```lisp
;; (defstruct game ... (wm (textquest.reasoning:make-wm)) ...)
```

---

## 5) Example: slots/fillers + productions in action

### Populate the world as frames (slot/filler facts)

```lisp
(let ((db (textquest.reasoning:wm-db (game-wm *game*))))
  (fdb-assert! db 'player :at 'tavern)
  (fdb-assert! db 'tavern :desc "Warm light. Loud laughter.")
  (fdb-assert! db 'tavern :exit '(north alley))
  (fdb-assert! db 'alley  :desc "Cold. Wet stone.")
  (fdb-assert! db 'alley  :exit '(south tavern)))
```

### Productions to derive affordances (“can-go”)

```lisp
(textquest.reasoning:defprod can-go (:salience 10)
  ((player :at ?room)
   (?room :exit (?dir ?to)))
  nil
  ((:assert player :can-go (?dir ?to))))
```

Now after you run:

```lisp
(run-productions! (wm-db (game-wm *game*)))
```

Working memory will contain derived facts like:
- `(player :can-go (north alley))`

And your `go` action can check that slot instead of recomputing.

---

## 6) “Filler database” retrieval patterns you’ll love

- **All exits from current room:**
```lisp
(fdb-values db room :exit)
```

- **Everything known about an entity:**
```lisp
(mapcar (lambda (slot) (list slot (fdb-values db ent slot)))
        (fdb-all-slots db ent))
```

- **Who has tag :hostile?**
```lisp
(fdb-entities-with db :tag :hostile)
```

- **Fast “describe room” using fillers:**
```lisp
(let ((desc (fdb-get db room :desc "Nothing special.")))
  (format nil "~A" desc))
```

---

## 7) Where this plugs into the game loop

Typical turn:

1) Player inputs command  
2) You assert command intent into WM (as slots/fillers)  
3) Run productions to derive consequences + options  
4) Execute the chosen action  
5) Cleanup “ephemeral” intent slots

Example:

```lisp
;; Before reasoning
(fdb-assert! db 'player :intent '(go north))

;; Deduce consequences
(run-productions! db)

;; Then your game action layer reads:
;; (fdb-values db 'player :can-go) etc.
```

---

If you want the next “real” upgrade, tell me which direction:

1) **Refraction / agenda** (avoid infinite firing, better conflict resolution)  
2) **Negative conditions** (`:not` patterns like OPS5)  
3) **Working-memory “timestamps”** (facts expire after N turns)  
4) **A DSL**: `(defroom ...)` expands directly into FDB asserts + auto productions

I can drop in whichever one you want with the same style of small, runnable Lisp modules.

Here’s a working, “real macOS installer” path for a **Common Lisp (SBCL) text game** using a **.pkg**. I’ll give you a simple setup that installs:

- your executable to `/usr/local/bin/textquest` (so you can run it in Terminal)
- your game data to `/Library/Application Support/TextQuest/`
- optional save folder to `~/Library/Application Support/TextQuest/`

(You can also make a `.app` and install into `/Applications`—I’ll show that too.)

---

## Option 1: PKG that installs a command-line game (simplest)

### 1) Build your game binary
Assume you already build to:

```
dist/textquest
```

Test it:

```bash
./dist/textquest
```

### 2) Create a packaging “root” folder
In your project root:

```bash
rm -rf pkgroot
mkdir -p pkgroot/usr/local/bin
mkdir -p "pkgroot/Library/Application Support/TextQuest"
```

Copy your binary + assets:

```bash
cp dist/textquest pkgroot/usr/local/bin/textquest
chmod 755 pkgroot/usr/local/bin/textquest

cp -R assets/* "pkgroot/Library/Application Support/TextQuest/"
```

If you have a default world file:

```bash
mkdir -p "pkgroot/Library/Application Support/TextQuest/worlds"
cp -R assets/worlds/* "pkgroot/Library/Application Support/TextQuest/worlds/"
```

### 3) Build the .pkg with `pkgbuild`
```bash
pkgbuild \
  --root pkgroot \
  --identifier com.yourname.textquest \
  --version 1.0.0 \
  --install-location / \
  dist/TextQuest-1.0.0.pkg
```

### 4) Install-test locally
Double-click `dist/TextQuest-1.0.0.pkg`, then verify:

```bash
which textquest
textquest
ls "/Library/Application Support/TextQuest"
```

---

## Option 2: PKG that installs a double-clickable .app into /Applications

### 1) Create an `.app` bundle
Make this structure:

```bash
rm -rf build/TextQuest.app
mkdir -p build/TextQuest.app/Contents/{MacOS,Resources}
```

Add an `Info.plist`:

```xml
<!-- build/TextQuest.app/Contents/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TextQuest</string>
  <key>CFBundleDisplayName</key><string>TextQuest</string>
  <key>CFBundleIdentifier</key><string>com.yourname.textquest</string>
  <key>CFBundleVersion</key><string>1.0.0</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleExecutable</key><string>TextQuest</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict>
</plist>
```

Copy your compiled binary as the app executable:

```bash
cp dist/textquest build/TextQuest.app/Contents/MacOS/TextQuest
chmod 755 build/TextQuest.app/Contents/MacOS/TextQuest
```

Put assets into Resources:

```bash
cp -R assets build/TextQuest.app/Contents/Resources/assets
```

**Important:** Your game should locate assets relative to the app when double-clicked. In Lisp, you can:
- check if you’re inside an app bundle and derive `Resources/` path, or
- let the installer also place assets in `/Library/Application Support/TextQuest/` and always read from there.

### 2) Stage for pkgroot
```bash
rm -rf pkgroot
mkdir -p pkgroot/Applications
cp -R build/TextQuest.app pkgroot/Applications/
```

### 3) Build the pkg
```bash
pkgbuild \
  --root pkgroot \
  --identifier com.yourname.textquest \
  --version 1.0.0 \
  --install-location / \
  dist/TextQuestApp-1.0.0.pkg
```

Install it, then check `/Applications/TextQuest.app`.

---

## Add a postinstall script (create per-user save folder)

macOS PKG scripts run as root. You can create common dirs and set permissions.

Create:

```
scripts/postinstall
```

```bash
#!/bin/bash
set -e

APP_SUPPORT="/Library/Application Support/TextQuest"
mkdir -p "$APP_SUPPORT"
chmod -R 755 "$APP_SUPPORT" || true

# Optional: create a shared saves directory (system-wide)
mkdir -p "$APP_SUPPORT/saves"
chmod -R 777 "$APP_SUPPORT/saves" || true

exit 0
```

Make executable:

```bash
chmod +x scripts/postinstall
```

Then build with scripts:

```bash
pkgbuild \
  --root pkgroot \
  --scripts scripts \
  --identifier com.yourname.textquest \
  --version 1.0.0 \
  --install-location / \
  dist/TextQuest-1.0.0.pkg
```

(If you want per-user saves under `~/Library/...`, best practice is: create it on first run from within the game, not from the installer.)

---

## (Recommended) Use `productbuild` for a nicer installer wrapper
`pkgbuild` makes a component pkg. `productbuild` wraps it into a distribution pkg.

```bash
productbuild \
  --package dist/TextQuest-1.0.0.pkg \
  dist/TextQuestInstaller-1.0.0.pkg
```

---

## Code signing + notarization (only if you distribute broadly)
If you’re sharing outside your own machines, you’ll usually need:
- sign the app/binary
- sign the pkg
- notarize

High level:

```bash
codesign --force --deep --sign "Developer ID Application: YOUR NAME" /path/to/TextQuest.app
productsign --sign "Developer ID Installer: YOUR NAME" unsigned.pkg signed.pkg
xcrun notarytool submit signed.pkg --keychain-profile "notary-profile" --wait
xcrun stapler staple signed.pkg
```

If you’re just installing locally (or within your own network), you can skip notarization.

---

## Make your game find its installed assets (important)

If you install assets to:

`/Library/Application Support/TextQuest/`

then in Lisp, set your asset base like:

- use env var override (nice for dev): `TEXTQUEST_DATA_DIR`
- else default to that path

Example behavior:
- Dev: load from `./assets`
- Installed: load from `/Library/Application Support/TextQuest`

If you want, paste your current “load assets” Lisp code (or your folder layout) and I’ll give you a tiny `data-dir` function that works for both CLI + `.app`.

---

### Quick “one command” build script (copy/paste)
If you want the “CLI PKG” version in one go:

```bash
#!/bin/bash
set -e
VERSION="1.0.0"
ID="com.yourname.textquest"

rm -rf pkgroot
mkdir -p pkgroot/usr/local/bin
mkdir -p "pkgroot/Library/Application Support/TextQuest"

cp dist/textquest pkgroot/usr/local/bin/textquest
chmod 755 pkgroot/usr/local/bin/textquest

cp -R assets/* "pkgroot/Library/Application Support/TextQuest/"

pkgbuild --root pkgroot --identifier "$ID" --version "$VERSION" --install-location / "dist/TextQuest-$VERSION.pkg"
echo "Built dist/TextQuest-$VERSION.pkg"
```

---

If you tell me which install style you want:
1) **Terminal command** (`/usr/local/bin/textquest`)  
2) **Double-click app** (`/Applications/TextQuest.app`)  
…I’ll tailor the exact pkgroot layout + scripts + the Lisp “asset path resolver” to match.

Below is a clean **chronological backtracking** upgrade that fits your setup (WM frames + productions agenda + coroutines + time agenda). This gives you:

- **Undo / rewind** (go back N turns)
- **Chronological backtracking search** (DFS over choices with a trail stack + choicepoints)
- Works with your **slot/filler DB** and **production system**, without trying to serialize closures

---

## 1) Project structure update

```
src/
  core/
    util.lisp
    errors.lisp
    log.lisp
    time.lisp
    agenda.lisp
    coro.lisp

    trail.lisp            ; NEW: reversible "trail" of changes

  reasoning/
    frames.lisp
    wm.lisp
    productions.lisp
    conflict.lisp
    fire.lisp
    agenda.lisp
    backtrack.lisp        ; NEW: chronological backtracking engine (choicepoints)

  game/
    state.lisp
    world.lisp
    actions.lisp
    rules.lisp
    undo.lisp             ; NEW: per-turn checkpoints + rewind API

  scripting/
    scripts.lisp
    cutscenes.lisp
```

Add exports in `packages.lisp` (short version):

- `textquest.core`: `with-trail`, `mark`, `undo-to-mark`
- `textquest.reasoning`: `with-choicepoint`, `choose`, `backtrack-run`
- `textquest.game`: `checkpoint!`, `rewind!`

---

## 2) The key idea (chronological backtracking)

We maintain a **TRAIL** (stack) of reversible operations:

- frame asserts/retracts `(ent slot filler)`  
- agenda scheduling/pop (optional)  
- changes to scalar fields (turn count, hp, flags) via reversible “setf”

And we maintain **CHOICEPOINTS**:

- a mark in the trail
- a list of remaining alternatives
- any metadata (depth, reason)

When a branch fails, we **undo to the mark** and try the next alternative. That’s chronological backtracking.

---

## 3) Reversible trail (core) — `src/core/trail.lisp`

This is small but powerful.

```lisp
(in-package #:textquest.core)

(defstruct trail
  (ops '()))   ; stack of (lambda () ...) undo-thunks

(defvar *trail* nil)

(defmacro with-trail ((&optional (tr '(make-trail))) &body body)
  `(let ((*trail* ,tr))
     ,@body))

(defun trail-push-undo! (undo-fn)
  (when *trail*
    (push undo-fn (trail-ops *trail*))))

(defun mark ()
  "Return an integer mark you can undo back to."
  (if *trail* (length (trail-ops *trail*)) 0))

(defun undo-to-mark (m)
  "Undo all operations down to mark M."
  (when *trail*
    (loop while (> (length (trail-ops *trail*)) m) do
      (let ((u (pop (trail-ops *trail*))))
        (funcall u))))
  t)

(defmacro tsetf (place value)
  "Reversible SETF for scalar places."
  (let ((old (gensym "OLD")))
    `(let ((,old ,place))
       (trail-push-undo! (lambda () (setf ,place ,old)))
       (setf ,place ,value))))
```

You’ll use `tsetf` for game scalars (HP, turn, flags), and wrap your rule/action execution in `with-trail`.

---

## 4) Make your slot/filler DB reversible (frames integration)

In `reasoning/frames.lisp`, change `fdb-assert!` / `fdb-retract!` to record undo ops.

Assuming you already have:

- `fdb-assert! db ent slot filler`
- `fdb-retract! db ent slot filler`

Update them like this (minimal, safe):

```lisp
(in-package #:textquest.reasoning)

(defun fdb-has? (db ent slot filler)
  (member filler (fdb-values db ent slot) :test #'equal))

(defun fdb-assert! (db ent slot filler)
  (unless (fdb-has? db ent slot filler)
    ;; record undo: retract what we just asserted
    (textquest.core:trail-push-undo!
     (lambda () (ignore-errors (fdb-retract! db ent slot filler))))
    ;; ... your existing insert logic here ...
    ;; (do the actual assert)
    )
  (list ent slot filler))

(defun fdb-retract! (db ent slot filler)
  (when (fdb-has? db ent slot filler)
    ;; record undo: re-assert what we just retracted
    (textquest.core:trail-push-undo!
     (lambda () (ignore-errors (fdb-assert! db ent slot filler))))
    ;; ... your existing remove logic here ...
    )
  (list ent slot filler))
```

**Important:** indexes can remain “conservative” like before; as long as `fdb-values` and `fdb-all-facts` reflect truth, undo stays correct.

---

## 5) Backtracking engine (choicepoints) — `src/reasoning/backtrack.lisp`

This gives you `choose` + `with-choicepoint` + `backtrack-run`.

```lisp
(in-package #:textquest.reasoning)

(defstruct choicepoint
  mark
  alts
  name)

(defvar *cp-stack* nil)

(defun push-choicepoint (name alts)
  (let ((cp (make-choicepoint :mark (textquest.core:mark)
                              :alts alts
                              :name name)))
    (push cp *cp-stack*)
    cp))

(defun pop-choicepoint () (pop *cp-stack*))

(defun fail (&optional (why :fail))
  "Trigger chronological backtracking."
  (declare (ignore why))
  (throw :bt-fail t))

(defun choose (name alts)
  "Pick first alt; store rest for backtracking."
  (unless alts (fail :no-alts))
  (push-choicepoint name (rest alts))
  (first alts))

(defun backtrack-step ()
  "Undo to last choicepoint and try next alternative."
  (loop while *cp-stack* do
    (let ((cp (first *cp-stack*)))
      (when (choicepoint-alts cp)
        (let ((next (pop (choicepoint-alts cp))))
          (textquest.core:undo-to-mark (choicepoint-mark cp))
          ;; keep cp on stack if it still has alts; else pop it later
          (return next)))
      (pop-choicepoint)))
  nil)

(defun backtrack-run (thunk &key (max-tries 10000))
  "Run THUNK, backtracking on (fail). Returns (values result :ok) or (values nil :exhausted)."
  (let ((tries 0))
    (catch :bt-top
      (loop
        (incf tries)
        (when (> tries max-tries)
          (return-from backtrack-run (values nil :max-tries)))
        (let ((ok
                (catch :bt-fail
                  (let ((r (funcall thunk)))
                    (return-from backtrack-run (values r :ok))))))

          ;; on failure, try next alternative
          (declare (ignore ok))
          (let ((next (backtrack-step)))
            (unless next
              (return-from backtrack-run (values nil :exhausted)))
            ;; store NEXT somewhere accessible; simplest: a dynamic var
            (setf *next-choice* next)))))))

(defvar *next-choice* nil)
```

### How you use it
You write your search as a function that repeatedly calls `choose`. When a branch fails, call `fail`.

---

## 6) Where “chronological” matters: integrate with productions + agendas + coroutines

### Rule firing / action execution
Wrap each attempt/turn in a trail:

```lisp
(textquest.core:with-trail ()
  ;; assert intent
  ;; run production agenda (fires reversible fdb changes)
  ;; apply action (use tsetf for scalars)
  ;; if invalid -> (textquest.reasoning:fail)
  )
```

### Scalars (turn, HP, flags)
Use `tsetf`:

```lisp
(textquest.core:tsetf (textquest.game:game-turn game)
                      (1+ (textquest.game:game-turn game)))
```

### Agendas
If you want agendas to be backtrackable, represent them as data lists and mutate them only through reversible operations (push/pop with undo thunks). Minimal approach: **checkpoint agenda as data** in undo module (below) instead of trailing every internal queue op.

### Coroutines
Don’t trail closures. Trail only **coroutine state** as data (state index, status, waiting reason). Use `tsetf` to update `coro-state`/`coro-status`.

---

## 7) Per-turn chronological backtracking (rewind/undo) — `src/game/undo.lisp`

This is “player undo” and also very useful for debugging.

```lisp
(in-package #:textquest.game)

(defstruct checkpoint
  turn
  trail-mark
  cp-depth)     ; choicepoint stack depth at that time (optional)

(defparameter *checkpoints* '())

(defun checkpoint! (game)
  (push (make-checkpoint :turn (game-turn game)
                         :trail-mark (textquest.core:mark)
                         :cp-depth (length textquest.reasoning::*cp-stack*))
        *checkpoints*)
  (first *checkpoints*))

(defun rewind! (game &key (turns 1))
  "Undo N turns worth of changes (chronological)."
  (declare (ignore game))
  (dotimes (_ turns)
    (unless *checkpoints* (return))
    (let ((cp (pop *checkpoints*)))
      (textquest.core:undo-to-mark (checkpoint-trail-mark cp))
      ;; optional: truncate choicepoints stack to cp-depth
      (setf textquest.reasoning::*cp-stack*
            (subseq textquest.reasoning::*cp-stack*
                    0 (min (checkpoint-cp-depth cp)
                           (length textquest.reasoning::*cp-stack*)))))))
```

Call `checkpoint!` once per committed turn (after input is accepted), so “undo” rewinds cleanly.

---

## 8) Example: chronological backtracking over actions

Say your game is trying to automatically find a path / solve a puzzle.

```lisp
(defun try-solve (game)
  (textquest.core:with-trail ()
    (let* ((db (textquest.reasoning:wm-db (game-wm game)))
           (move (textquest.reasoning:choose 'move '(:north :east :south :west))))
      ;; attempt move
      (unless (textquest.game:attempt-move! game move)
        (textquest.reasoning:fail :blocked))
      ;; run productions after move
      (textquest.reasoning:run-productions/agenda! db)
      ;; success condition?
      (when (textquest.game:at-goal? game)
        (return-from try-solve (list :solved move)))
      ;; otherwise keep searching deeper by recursion
      (try-solve game))))
```

Then:

```lisp
(multiple-value-bind (res status)
    (textquest.reasoning:backtrack-run (lambda () (try-solve *game*)))
  (format t "~&Result=~S status=~S~%" res status))
```

This is chronological DFS: it always backtracks to the **most recent** choicepoint.

---

## 9) What you get immediately

- **Chronological backtracking**: `choose` + `fail` + `backtrack-run`
- **Reversible world updates** via the trail (frames asserts/retracts)
- **Undo feature** with per-turn checkpoints
- Works with your **production system** because its effects are just DB changes (now trailed)

---

## 10) Two important knobs (pick one now, easy later)

### A) Trail everything (fine-grained)
Every `fdb-assert!` / `fdb-retract!` / `tsetf` is reversible → best for deep search.

### B) Snapshot at choicepoints (coarse)
At each choicepoint, store snapshot of `(triples + scalars + agenda + coro states)` and restore on backtrack. Simpler but heavier.

You already have a save snapshot pipeline; if you want, I can implement **choicepoint snapshots** using your `game->sexp` / `sexp->game!` instead of trailing.

---

If you want the *most “AI textbook”* version next, I can add:
- **refraction-aware backtracking** (so refraction table also rewinds)
- **dependency-directed backjumping** (skip irrelevant choicepoints)
- **chronological + agenda** integration (choicepoints per agenda group/focus)

Got it — if the game is a **simulation that runs forever**, you still *can* use coroutines/agendas/productions, but you need to change how you think about **backtracking + persistence**:

- You don’t “search to a final solution”
- You use **bounded backtracking** for *what-if*, *rollback*, *debug*, *AI planning*, or *recover from bad states*
- You persist with **rolling snapshots + event logs** so the sim can run indefinitely without memory blowups

Here’s the concrete update.

---

## Architecture changes for an infinite simulation

### 1) Time is unbounded → use **rolling state management**
Add:
- **checkpoints ring buffer** (keep last N turns or last X minutes)
- optional **event-sourcing log** (append-only actions/events)
- periodic **snapshot** (full state) so you can restart fast

### 2) Backtracking must be **bounded**
Chronological backtracking becomes:
- “rewind up to window W”
- “branch for K steps”
- then either **commit** or **discard** the branch

### 3) Coroutines must be **serializable by data**
No closures in save/backtrack. Coroutines store:
- `name` + `pc` (program counter) + `state` data + `wait-condition`
and are resumed by looking up `name` in a registry.

---

## Updated project structure (infinite sim ready)

```
src/
  core/
    time.lisp
    agenda.lisp
    coro.lisp
    trail.lisp
    ring.lisp              ; NEW: ring buffer utility
    snapshot.lisp          ; NEW: snapshot/restore helpers

  reasoning/
    frames.lisp
    wm.lisp
    productions.lisp
    conflict.lisp
    fire.lisp
    backtrack.lisp         ; bounded backtracking controller

  sim/
    loop.lisp              ; NEW: forever loop + tick pipeline
    checkpoint.lisp        ; NEW: rolling checkpoints policy
    events.lisp            ; NEW: event log (append-only)
    metrics.lisp           ; NEW: counters, health, drift detection

  game/
    state.lisp
    actions.lisp
    undo.lisp              ; now “rewind within window”
```

---

## The tick pipeline (forever loop)

Each tick/turn:

1) **advance clock**
2) run **due agenda items**
3) resume **coroutines**
4) run **production agenda** (derive consequences)
5) apply **external inputs** (if any)
6) **checkpoint + persist policy**

That order keeps the sim deterministic and debuggable.

---

## Rolling checkpoints (don’t store infinite history)

### Policy
- Keep last **N turns** of reversible trail ops (fast rewind)
- Every **M turns**, write a **snapshot** to disk
- Optionally append events to an **event log** each tick

Typical values:
- `N = 5,000 turns` (rewind window)
- `M = 1,000 turns` (snapshot frequency)

Memory stays bounded.

### What to store in a checkpoint
Store *only*:
- the **trail mark**
- a few scalar counters
- optional: agenda length, coroutine registry versions

You do **not** keep infinite trail — you prune it.

---

## Bounded chronological backtracking (“branch mode”)

Add a “branch runner” that:
- saves current mark
- runs speculative steps for K ticks
- if happy → keep changes
- if not → undo to mark

Conceptually:

- **commit** = do nothing (keep modifications)
- **abort** = `undo-to-mark`

This is perfect for:
- NPC planning
- policy evaluation
- testing rule changes
- recovering from unstable states

### What changes from earlier backtracking
- Choicepoints can exist, but only within a **bounded horizon**
- After horizon ends, you *must* either commit or revert
- You periodically “forget” old choicepoints/checkpoints beyond window

---

## Persistence for an infinite sim

### Best practice combo
1) **Snapshot** (`state.sexp`) every M turns  
2) **Event log** (`events.log`) append each tick  
3) On restart: load snapshot, then replay events since snapshot

This is how “runs forever” systems stay robust.

**Why it’s better than only snapshots**
- if you crash, you lose at most “events since last flush”
- event logs are small and compressible
- debugging becomes easy (“replay to reproduce bug”)

---

## Coroutines in an infinite sim

Make coroutines data-driven:

- `(:name npc-brain :pc 12 :state (...) :waiting (:until-turn 50012))`

On save/backtrack you just serialize that data.

Resume uses a registry:

- `npc-brain` → step function
- step function switches on `pc` and updates state

That makes your forever sim:
- deterministic
- persistable
- backtrackable within the window

---

## What you should implement next (minimal set)

If you want the smallest change set that makes “forever” safe:

1) **Ring buffer checkpoints**
2) **Snapshot every M turns**
3) **Branch mode** (commit/abort) using your trail
4) **Coroutine registry** (no closure persistence)

---

## Quick rule of thumb for your setup

- Use **trail-based undo** for the most recent window (fast)
- Use **snapshots** for long-running durability
- Use **event log** if you care about replay/debug/reproducibility
- Use **backtracking** only inside “branch mode” horizons

---

If you tell me one detail, I’ll tailor the exact code patterns:

- Do you want the sim to tick in **real time** (e.g., 60 Hz / seconds), or in **turns as fast as possible** (headless batch sim)?

- Here’s a solid way to implement a **calendar inside an infinite simulation** that already has **agendas + coroutines + productions**.

The core idea: keep a **simulation clock** (absolute date/time), plus a **calendar scheduler** that can fire:

- one-off events at a specific datetime
- recurring events (daily/weekly/monthly) like “every Monday 09:00”
- rule-driven events (“on first day of month, pay rent”)

All of this stays **deterministic**, **persistable**, and **bounded-memory**.

---

## 1) Add calendar modules to project structure

```
src/
  core/
    time.lisp
    agenda.lisp
    ring.lisp
    snapshot.lisp

  sim/
    loop.lisp
    checkpoint.lisp

  calendar/
    datetime.lisp          ; date math + comparisons
    clock.lisp             ; sim clock: now, advance, tick size
    schedule.lisp          ; recurrence specs (daily/weekly/monthly)
    calendar.lisp          ; event store + next-fire computation
    integration.lisp       ; hooks into core agenda / productions
    persist.lisp           ; snapshot/restore calendar state
```

Add a new package `textquest.calendar`.

---

## 2) Represent simulation time (no OS time)

Use a simple **Gregorian datetime struct** and comparison utilities. Keep it pure-data for saves.

### `src/calendar/datetime.lisp`

```lisp
(in-package #:textquest.calendar)

(defstruct dt
  (year 1970 :type fixnum)
  (month 1 :type fixnum)   ; 1..12
  (day 1 :type fixnum)     ; 1..31
  (hour 0 :type fixnum)    ; 0..23
  (min 0 :type fixnum)     ; 0..59
  (sec 0 :type fixnum))    ; 0..59

(defun dt< (a b)
  (or (< (dt-year a) (dt-year b))
      (and (= (dt-year a) (dt-year b))
           (or (< (dt-month a) (dt-month b))
               (and (= (dt-month a) (dt-month b))
                    (or (< (dt-day a) (dt-day b))
                        (and (= (dt-day a) (dt-day b))
                             (or (< (dt-hour a) (dt-hour b))
                                 (and (= (dt-hour a) (dt-hour b))
                                      (or (< (dt-min a) (dt-min b))
                                          (and (= (dt-min a) (dt-min b))
                                               (< (dt-sec a) (dt-sec b))))))))))))

(defun dt<= (a b) (or (dt< a b) (dt= a b)))

(defun dt= (a b)
  (and (= (dt-year a) (dt-year b))
       (= (dt-month a) (dt-month b))
       (= (dt-day a) (dt-day b))
       (= (dt-hour a) (dt-hour b))
       (= (dt-min a) (dt-min b))
       (= (dt-sec a) (dt-sec b))))

(defun leap-year-p (y)
  (and (zerop (mod y 4))
       (or (not (zerop (mod y 100)))
           (zerop (mod y 400)))))

(defun days-in-month (y m)
  (cond
    ((= m 2) (if (leap-year-p y) 29 28))
    ((member m '(1 3 5 7 8 10 12)) 31)
    (t 30)))
```

---

## 3) Sim clock: dt + step size

Decide your sim tick granularity (common: **1 second**, **1 minute**, or **1 turn = 10 minutes**).

### `src/calendar/clock.lisp`

```lisp
(in-package #:textquest.calendar)

(defstruct sim-clock
  (now (make-dt) :type dt)
  ;; tick size in seconds (e.g., 60 = 1 minute per sim tick)
  (tick-seconds 60 :type fixnum))

(defun normalize-dt! (d)
  (labels ((carry (field limit inc-next get set set-next)
             (let ((v (funcall get)))
               (when (>= v limit)
                 (let ((q (floor v limit))
                       (r (mod v limit)))
                   (funcall set r)
                   (funcall set-next (+ (funcall inc-next) q)))))))
    ;; seconds -> minutes
    (carry 'sec 60
           (lambda () (dt-min d))
           (lambda () (dt-sec d))
           (lambda (x) (setf (dt-sec d) x))
           (lambda (x) (setf (dt-min d) x)))
    ;; minutes -> hours
    (carry 'min 60
           (lambda () (dt-hour d))
           (lambda () (dt-min d))
           (lambda (x) (setf (dt-min d) x))
           (lambda (x) (setf (dt-hour d) x)))
    ;; hours -> days
    (when (>= (dt-hour d) 24)
      (let ((q (floor (dt-hour d) 24))
            (r (mod (dt-hour d) 24)))
        (setf (dt-hour d) r)
        (incf (dt-day d) q)))
    ;; days -> month/year
    (loop
      with dim = (days-in-month (dt-year d) (dt-month d))
      while (> (dt-day d) dim) do
        (decf (dt-day d) dim)
        (incf (dt-month d))
        (when (> (dt-month d) 12)
          (setf (dt-month d) 1)
          (incf (dt-year d)))
        (setf dim (days-in-month (dt-year d) (dt-month d)))))
  d)

(defun clock-advance! (clk &optional (ticks 1))
  (let ((d (sim-clock-now clk)))
    (incf (dt-sec d) (* ticks (sim-clock-tick-seconds clk)))
    (normalize-dt! d)
    d))
```

---

## 4) Calendar events: one-shot + recurring

### Event model

- **One-shot**: fires once at `dt`
- **Recurring**: schedule rule → produces the next `dt` after “now”
- Each event has an `id`, `title`, `payload` (what to do), and `next-fire`

### `src/calendar/schedule.lisp` (simple recurrence)

Support a few high-value rules (you can grow later):

- `(:daily :at (hour min))`
- `(:weekly :by-dow (0..6) :at (hour min))`  (0=Sunday)
- `(:monthly :by-dom (1..31) :at (hour min))`

We’ll need day-of-week; use a known algorithm (same as earlier month printing).

```lisp
(in-package #:textquest.calendar)

(defun day-of-week (y m d)
  "0=Sunday..6=Saturday"
  (let* ((t #(0 3 2 5 0 3 5 1 4 6 2 4))
         (y2 (if (< m 3) (1- y) y)))
    (mod (+ y2 (floor y2 4) (- (floor y2 100)) (floor y2 400)
            (aref t (1- m)) d)
         7)))

(defun dt->dow (dt)
  (day-of-week (dt-year dt) (dt-month dt) (dt-day dt)))

(defun make-next-dt-same-day (now hour min)
  (make-dt :year (dt-year now) :month (dt-month now) :day (dt-day now)
           :hour hour :min min :sec 0))

(defun dt-add-days (dt n)
  (let ((x (copy-dt dt)))
    (incf (dt-day x) n)
    (normalize-dt! x)))

(defun next-occurrence (spec now)
  "Return next dt strictly after NOW for schedule SPEC."
  (ecase (first spec)
    (:daily
     (destructuring-bind (_ &key at) spec
       (declare (ignore _))
       (destructuring-bind (h m) at
         (let ((cand (make-next-dt-same-day now h m)))
           (if (dt< now cand) cand (dt-add-days cand 1))))))

    (:weekly
     (destructuring-bind (_ &key by-dow at) spec
       (declare (ignore _))
       (destructuring-bind (h m) at
         (let* ((cand0 (make-next-dt-same-day now h m))
                (dow-now (dt->dow now)))
           ;; start from today (or tomorrow if time passed), then find next matching DOW
           (when (not (dt< now cand0))
             (setf cand0 (dt-add-days cand0 1))
             (setf dow-now (mod (1+ dow-now) 7)))
           (loop for i from 0 to 7 do
             (let ((dow (mod (+ dow-now i) 7)))
               (when (member dow by-dow)
                 (return (dt-add-days cand0 i)))))))))

    (:monthly
     (destructuring-bind (_ &key by-dom at) spec
       (declare (ignore _))
       (destructuring-bind (h m) at
         (labels ((mk (y mo dom)
                    (make-dt :year y :month mo :day dom :hour h :min m :sec 0)))
           (let* ((y (dt-year now)) (mo (dt-month now))
                  (dom (min by-dom (days-in-month y mo)))
                  (cand (mk y mo dom)))
             (if (dt< now cand)
                 cand
                 (progn
                   (incf mo)
                   (when (> mo 12) (setf mo 1) (incf y))
                   (setf dom (min by-dom (days-in-month y mo)))
                   (mk y mo dom))))))))))
```

---

## 5) Calendar store + integration with agenda

Keep events in a list/heap keyed by `next-fire`. Each sim tick, you:

1) advance clock
2) pop & fire all events where `next-fire <= now`
3) if recurring, compute next and reinsert

### `src/calendar/calendar.lisp`

```lisp
(in-package #:textquest.calendar)

(defstruct cal-event
  id
  title
  (kind :one-shot)          ; :one-shot | :recurring
  at                        ; dt for one-shot
  schedule                  ; recurrence spec for recurring
  payload                   ; pure data, not a closure
  next-fire)                ; dt (cached)

(defstruct calendar
  (events '())              ; sorted by next-fire
  (next-id 1))

(defun %sort-events (evs)
  (sort evs (lambda (a b) (dt< (cal-event-next-fire a) (cal-event-next-fire b)))))

(defun calendar-add-one-shot! (cal title at payload)
  (let ((ev (make-cal-event :id (calendar-next-id cal)
                            :title title
                            :kind :one-shot
                            :at at
                            :payload payload
                            :next-fire at)))
    (incf (calendar-next-id cal))
    (setf (calendar-events cal) (%sort-events (cons ev (calendar-events cal))))
    ev))

(defun calendar-add-recurring! (cal title schedule now payload)
  (let* ((nf (next-occurrence schedule now))
         (ev (make-cal-event :id (calendar-next-id cal)
                             :title title
                             :kind :recurring
                             :schedule schedule
                             :payload payload
                             :next-fire nf)))
    (incf (calendar-next-id cal))
    (setf (calendar-events cal) (%sort-events (cons ev (calendar-events cal))))
    ev))

(defun calendar-pop-due (cal now)
  "Pop and return all events with next-fire <= now."
  (let ((due '()))
    (loop while (and (calendar-events cal)
                     (dt<= (cal-event-next-fire (first (calendar-events cal))) now))
          do (push (pop (calendar-events cal)) due))
    (nreverse due)))

(defun calendar-tick! (cal clk fire-fn)
  "Advance handled externally; this just fires due events at clk.now."
  (let* ((now (sim-clock-now clk))
         (due (calendar-pop-due cal now)))
    (dolist (ev due)
      (funcall fire-fn ev)
      (when (eql (cal-event-kind ev) :recurring)
        (setf (cal-event-next-fire ev) (next-occurrence (cal-event-schedule ev) now))
        (setf (calendar-events cal) (%sort-events (cons ev (calendar-events cal))))))))
```

**Important**: `payload` is **data** (e.g., `(:assert player :bill-due :rent)`), not a closure, so it saves cleanly.

---

## 6) Firing calendar events into your simulation (WM + productions)

A nice pattern: firing an event **asserts facts** into WM/frames, and productions react.

### `src/calendar/integration.lisp`

```lisp
(in-package #:textquest.calendar)

(defun fire-into-wm (game ev)
  "Interpret EV payload as data-driven effects."
  (let* ((wm (textquest.game:game-wm game))
         (db (textquest.reasoning:wm-db wm))
         (p (cal-event-payload ev)))
    ;; Example payload DSL:
    ;; (:assert ent slot filler)
    ;; (:retract ent slot filler)
    ;; (:emit topic data) -> assert an event fact
    (ecase (first p)
      (:assert
       (destructuring-bind (_ ent slot filler) p
         (declare (ignore _))
         (textquest.reasoning:fdb-assert! db ent slot filler)))
      (:retract
       (destructuring-bind (_ ent slot filler) p
         (declare (ignore _))
         (textquest.reasoning:fdb-retract! db ent slot filler)))
      (:emit
       (destructuring-bind (_ topic data) p
         (declare (ignore _))
         (textquest.reasoning:fdb-assert! db 'sim :event (list topic data (cal-event-id ev))))))))
```

Then in your main sim tick:

- advance clock
- `calendar-tick!` with `(lambda (ev) (fire-into-wm game ev))`
- then run productions agenda to respond to new facts

---

## 7) Wiring into the forever simulation loop

In `game/state.lisp`, add:

- `(clock (textquest.calendar:make-sim-clock ...))`
- `(calendar (textquest.calendar:make-calendar))`

In `sim/loop.lisp` tick:

```lisp
(defun sim-tick! (game)
  (let ((clk (textquest.game:game-clock game))
        (cal (textquest.game:game-calendar game))
        (wm (textquest.game:game-wm game)))
    ;; 1) advance time
    (textquest.calendar:clock-advance! clk 1)

    ;; 2) fire calendar due events into WM
    (textquest.calendar:calendar-tick! cal clk (lambda (ev) (textquest.calendar:fire-into-wm game ev)))

    ;; 3) resume coroutines, run time agenda, etc...
    ;; 4) productions react to newly asserted facts
    (textquest.reasoning:run-productions/agenda! (textquest.reasoning:wm-db wm))))
```

---

## 8) Examples: calendar events you’ll actually use

### Rent due on the 1st of every month at 09:00
```lisp
(calendar-add-recurring! cal "Rent due"
  '(:monthly :by-dom 1 :at (9 0))
  (sim-clock-now clk)
  '(:emit :rent-due (:amount 1200)))
```

### NPC patrol every day at 22:00
```lisp
(calendar-add-recurring! cal "Night patrol"
  '(:daily :at (22 0))
  (sim-clock-now clk)
  '(:emit :npc-shift (:npc guard :mode patrol)))
```

### One-shot “festival starts”
```lisp
(calendar-add-one-shot! cal "Festival begins"
  (make-dt :year 2030 :month 7 :day 4 :hour 12 :min 0 :sec 0)
  '(:emit :festival :start))
```

Productions can then react to `(sim :event (...))` facts.

---

## 9) Persistence (snapshot-friendly)

To persist, store:
- clock `now` fields + `tick-seconds`
- calendar `next-id`
- event list with `id/title/kind/at/schedule/payload/next-fire`

Everything is simple S-expressions (no functions).

If you already have `game->sexp`, just add:

```lisp
:clock (clock->sexp ...)
:calendar (calendar->sexp ...)
```

and restore them on load.

---

## 10) Optional: “print a month” from sim time
If you want a UI `cal` view inside the sim (for debugging or in-game):

- use the same `day-of-week` + `days-in-month`
- generate a month grid for `(dt-year now, dt-month now)`
- mark days that have scheduled events (by scanning calendar events)

---

If you tell me your tick granularity (1 tick = **1 minute**? **1 hour**? **10 minutes**?), I can tighten the recurrence/next-fire logic to be super efficient (e.g., avoid sorting full lists each tick by using a binary heap or bucketed wheel).

Below is a **clean, simulation-grade way to model biological data** in your *forever-running* game. This fits your existing architecture (calendar, agendas, coroutines, productions, backtracking) and stays **data-driven, bounded, and evolvable**.

Think of biology as **slow processes over time**, not stats you recalc every tick.

---

## 1) Project structure update (biology as a subsystem)

```
src/
  biology/
    bio-core.lisp          ; traits, organisms, populations
    physiology.lisp        ; metabolism, energy, damage, repair
    genetics.lisp          ; genotype -> phenotype
    lifecycle.lisp         ; birth, aging, death
    disease.lisp           ; infection, immunity, recovery
    ecology.lisp           ; population dynamics, carrying capacity
    bio-agenda.lisp        ; slow biological scheduling
    bio-calendar.lisp      ; seasonal / circadian hooks
    bio-persist.lisp       ; snapshot/restore biology state
```

Biology **does not tick every turn**. It runs on:
- calendar events (daily, seasonal)
- agenda triggers (every N turns)
- condition changes (stress, starvation, infection)

---

## 2) Core biological model (frames + slots)

Everything biological is **frames with slots** (perfect for your WM + productions).

### Fundamental entities
- `organism` (player, NPC, animal, plant)
- `population` (wolves, bacteria colony)
- `pathogen`
- `nutrient`

### Slot/filler examples
```lisp
(player
  :species human
  :age-days 9125
  :sex male
  :mass-kg 78
  :energy 1850
  :health 0.92
  :hydration 0.81
  :immunity (flu measles)
  :infected (influenza)
  :metabolic-rate 1700
  :circadian-phase :day
)
```

This plugs directly into your `fdb`.

---

## 3) Physiology: slow state variables

### `src/biology/physiology.lisp`

Key idea: **rates**, not instant changes.

Slots:
- `:energy`
- `:hydration`
- `:oxygen`
- `:health`

Rates:
- `:metabolic-rate`
- `:water-loss-rate`
- `:healing-rate`
- `:damage-rate`

Example update rule (daily):

```lisp
(defprod daily-metabolism (:salience 5)
  ((?o :metabolic-rate ?m)
   (?o :energy ?e))
  nil
  ((:call bio:consume-energy ?o ?m)))
```

Energy consumption function:
```lisp
(defun consume-energy (org rate)
  (let ((e (fdb-get db org :energy)))
    (fdb-assert! db org :energy (max 0 (- e rate)))))
```

---

## 4) Genetics (optional but powerful)

### `src/biology/genetics.lisp`

Use **simple symbolic alleles**, not DNA strings.

```lisp
(:genotype
  (:size :large)
  (:metabolism :fast)
  (:immunity :strong))
```

Phenotype derivation (run once at birth):

```lisp
(defprod genotype->phenotype ()
  ((?o :genotype ?g))
  nil
  ((:call bio:apply-genotype ?o ?g)))
```

This is perfect for:
- procedural species
- evolution in infinite sims
- backtracking-safe reproduction

---

## 5) Lifecycle: aging, birth, death

### `src/biology/lifecycle.lisp`

Aging should run on **calendar days**, not turns.

Calendar event:
```lisp
(calendar-add-recurring! cal "Daily aging"
  '(:daily :at (0 0))
  (sim-clock-now clk)
  '(:emit :bio/day-tick nil))
```

Production reacting to it:
```lisp
(defprod age-organisms ()
  ((sim :event (:bio/day-tick ?_))
   (?o :age-days ?a))
  nil
  ((:assert ?o :age-days (+ ?a 1))))
```

Death condition:
```lisp
(defprod death ()
  ((?o :health ?h))
  (when (< ?h 0.01))
  ((:assert ?o :status :dead)))
```

---

## 6) Disease & immunity (data-driven)

### `src/biology/disease.lisp`

Pathogen entity:
```lisp
(influenza
  :infectivity 0.4
  :duration-days 7
  :damage-rate 0.02
  :immunity-granted influenza)
```

Infection is **just a fact**:
```lisp
(player :infected influenza)
```

Daily disease tick:
```lisp
(defprod disease-damage ()
  ((sim :event (:bio/day-tick ?_))
   (?o :infected ?p)
   (?p :damage-rate ?d))
  nil
  ((:call bio:apply-damage ?o ?d)))
```

Recovery:
```lisp
(defprod recovery ()
  ((?o :infected ?p)
   (?o :infection-days ?d)
   (?p :duration-days ?max))
  (when (>= ?d ?max))
  ((:retract ?o :infected ?p)
   (:assert ?o :immunity ?p)))
```

---

## 7) Ecology & populations (for infinite sims)

### `src/biology/ecology.lisp`

Populations are entities too:

```lisp
(wolves
  :population 42
  :growth-rate 0.03
  :carrying-capacity 80)
```

Logistic growth (monthly):

```lisp
(defprod population-growth ()
  ((sim :event (:bio/month-tick ?_))
   (?p :population ?n)
   (?p :growth-rate ?r)
   (?p :carrying-capacity ?k))
  nil
  ((:assert ?p :population
            (round (+ ?n (* ?r ?n (- 1 (/ ?n ?k))))))))
```

This allows:
- extinction
- overpopulation
- predator–prey modeling (via interactions)

---

## 8) Circadian & seasonal biology

### `src/biology/bio-calendar.lisp`

Hook calendar → biology:

- circadian rhythm (sleep / awake)
- seasonal metabolism
- mating seasons
- plant growth cycles

Example:
```lisp
(calendar-add-recurring! cal "Circadian flip"
  '(:daily :at (6 0))
  now
  '(:emit :bio/circadian :day))

(calendar-add-recurring! cal "Circadian flip"
  '(:daily :at (18 0))
  now
  '(:emit :bio/circadian :night))
```

Production:
```lisp
(defprod circadian-state ()
  ((sim :event (:bio/circadian ?phase))
   (?o :species human))
  nil
  ((:assert ?o :circadian-phase ?phase)))
```

---

## 9) Performance rules (important for “runs forever”)

### DO:
- Run biology **daily / hourly / monthly**, not per tick
- Use calendar + agenda batching
- Use productions only when triggering facts appear

### DON’T:
- Loop all organisms every tick
- Store biological history forever
- Use floats without clamping

---

## 10) Persistence (biological state)

Biology is already pure data:
- slots
- numbers
- symbols

So your existing snapshot system just works.

Add to snapshot:
```lisp
:biology (fdb-all-facts bio-db)
```

---

## 11) What this enables (immediately)

You now have:
- aging populations
- starvation & disease
- seasonal effects
- reproduction & extinction
- emergent behavior in infinite time

And all of it:
- deterministic
- backtrackable (bounded)
- calendar-driven
- rule-based

---

## Next optional upgrades (pick one)

1) **Evolution** (mutation + selection over generations)  
2) **Multi-scale time** (cells → organs → organisms → populations)  
3) **Energy-based economy** (food chains + thermodynamics)  
4) **Epidemiology** (SIR models with spatial spread)  

Tell me which direction you want and I’ll wire it directly into this biology subsystem.

To update your forever-sim with **new biological data** (new species, diseases, parameters, behaviors) without breaking running saves, do it as a **data migration + patch pipeline**.

Here’s a proven pattern that fits your frames/slots + productions + calendar.

---

## 1) Store a data/schema version in the world state

Add two slots in WM (or your snapshot root):

- `(sim :schema-version 3)`
- `(sim :data-version "2026-02-19")` (optional string/tag)

When you load a save, you run migrations until it reaches the latest schema version.

---

## 2) Split “content data” from “simulation state”

Keep two databases:

- **World/Content DB** (static-ish): species definitions, pathogen definitions, item templates  
- **State/WM DB** (dynamic): organisms, populations, current infections, energy, etc.

Updating “new data” usually means updating the **content DB** and then reconciling state.

Structure:

```
assets/
  bio/
    species.sexp
    pathogens.sexp
    nutrients.sexp
    patches/
      0003_add_reptiles.sexp
      0004_tune_flu_params.sexp
```

---

## 3) Use patch files (append-only) instead of rewriting everything

A patch is a list of operations like:

```lisp
(:assert influenza :damage-rate 0.015)
(:assert gecko :metabolic-rate 120)
(:retract oldvirus :infectivity 0.9)
(:upsert species/human :defaults (:hydration 0.8 :sleep-need 0.6))
```

**Rule:** patches must be idempotent (safe to apply twice).

---

## 4) Implement a patch applicator

Add `src/content/patch.lisp`:

### Patch operations (minimal set)
- `:assert ent slot filler`
- `:retract ent slot filler`
- `:set ent slot filler` (replace slot values)
- `:ensure ent slot filler` (assert only if missing)
- `:rename-entity old new` (optional)

Example implementation:

```lisp
(defun fdb-set-slot! (db ent slot filler)
  ;; remove existing fillers then assert new
  (dolist (v (textquest.reasoning:fdb-values db ent slot))
    (textquest.reasoning:fdb-retract! db ent slot v))
  (textquest.reasoning:fdb-assert! db ent slot filler))

(defun apply-op! (db op)
  (ecase (first op)
    (:assert
     (destructuring-bind (_ e s f) op
       (declare (ignore _))
       (textquest.reasoning:fdb-assert! db e s f)))
    (:retract
     (destructuring-bind (_ e s f) op
       (declare (ignore _))
       (textquest.reasoning:fdb-retract! db e s f)))
    (:set
     (destructuring-bind (_ e s f) op
       (declare (ignore _))
       (fdb-set-slot! db e s f)))
    (:ensure
     (destructuring-bind (_ e s f) op
       (declare (ignore _))
       (unless (member f (textquest.reasoning:fdb-values db e s) :test #'equal)
         (textquest.reasoning:fdb-assert! db e s f))))))

(defun apply-patch! (db ops)
  (dolist (op ops) (apply-op! db op))
  t)
```

Now “updating with new data” is just loading patch ops and applying them.

---

## 5) Add a migration step for running saves (schema evolution)

When loading a save:

1) read snapshot
2) restore WM/state
3) read `(sim :schema-version N)`
4) run migrations `N+1..LATEST`

Migration example (schema 2 → 3):
- you added `:hydration` but old saves don’t have it

```lisp
(defun migrate-2->3! (state-db)
  ;; For every organism with :species, ensure hydration exists.
  ;; (simpler if you keep a list of organisms somewhere)
  (dolist (org (textquest.reasoning:fdb-entities-with state-db :type :organism))
    (unless (textquest.reasoning:fdb-get state-db org :hydration nil)
      (textquest.reasoning:fdb-assert! state-db org :hydration 0.75)))
  (textquest.reasoning:fdb-set-slot! state-db 'sim :schema-version 3))
```

Keep migrations in:

```
src/migrate/
  migrate-0001.lisp
  migrate-0002.lisp
  migrate-0003.lisp
```

---

## 6) Reconcile content changes into state (important)

When you update species defaults or pathogen parameters, existing organisms might need recalculation.

Add a “reconcile pass” that:
- re-derives phenotype values
- clamps stats to new ranges
- updates derived rates

Example:
- you changed human `:metabolic-rate` default
- each organism should get new rate only if they haven’t customized it

Pattern:
- store “explicit vs default”
  - `(player :metabolic-rate (:explicit 1700))`
  - or absent means “use default”

Then reconcile:

```lisp
(defun effective (content-db state-db org slot)
  (or (textquest.reasoning:fdb-get state-db org slot nil)
      (let ((sp (textquest.reasoning:fdb-get state-db org :species nil)))
        (and sp (textquest.reasoning:fdb-get content-db sp slot nil)))))
```

So updates automatically influence behavior without rewriting state.

---

## 7) Hot updates while sim is running (live patch)

If the sim runs forever, you may want “apply patch now”:

- pause tick
- apply patch to content DB
- run reconcile pass
- resume

Make it a command in your CLI:

- `:load-patch assets/bio/patches/0004_tune_flu_params.sexp`

---

## 8) Persist “what patches have been applied”

Store in state:

- `(sim :applied-patches ("0003_add_reptiles" "0004_tune_flu_params"))`

So on startup you can:
- apply any missing patches
- avoid repeating work

---

## 9) Easiest workflow for you

1) Add new data by writing a patch file of ops  
2) Add migration only if schema changed (new required slots, new invariant)  
3) Reconcile derived values  
4) Save

---

If you tell me what “new data” means in your case (pick one), I’ll give you the exact patch + migration + reconcile code:

- new **species**
- new **disease/pathogen**
- new **trait slots** (schema change)
- new **calendar events** (seasonal biology)
- new **production rules** (logic update)

Below is a practical way to add a **Reason Maintenance System** to your Lisp sim—specifically a **Justification-based TMS (JTMS)** that can:

- record **why** a fact is believed (its justifications)
- automatically **retract derived facts** when supports disappear
- keep **explanations** (“this is true because…”)
- work with your **frames/slot-filler DB + productions + agendas**
- stay **persistent** (data-only) and compatible with your infinite sim

This is the “missing piece” once you start updating data live and running productions forever.

---

## 1) Project structure update

```
src/
  reasoning/
    frames.lisp
    wm.lisp
    productions.lisp
    conflict.lisp
    fire.lisp

    rms/
      jtms.lisp           ; NEW: nodes, justifications, belief update
      support.lisp        ; NEW: support sets, dependency graph indexes
      explain.lisp        ; NEW: explanation queries (why/why-not)
      integrate.lisp      ; NEW: hooks: assert/retract/derive from productions
      persist.lisp        ; NEW: serialize/restore JTMS state
```

Key idea: **Your DB stores facts. The JTMS stores reasons.**  
Derived facts get inserted/removed in the DB based on JTMS belief.

---

## 2) Core concepts (what we implement)

### Facts
Your existing triple: `(ent slot filler)`.

### Nodes
A JTMS “node” corresponds to one fact. It has:
- `:in?` whether believed
- `:assumption?` whether it’s a user/base fact
- list of **justifications** that can support it

### Justification
A rule application: **consequents** supported by **antecedents**.

Example:
- Antecedents: `(player :at tavern)` and `(tavern :exit (north alley))`
- Consequent: `(player :can-go (north alley))`
- Justification name: `can-go-rule`

When any antecedent is removed, JTMS can retract consequents that no longer have any valid support.

---

## 3) JTMS data structures — `src/reasoning/rms/jtms.lisp`

This is a compact, useful baseline.

```lisp
(in-package #:textquest.reasoning)

(defstruct jtms
  ;; fact -> node
  (nodes (make-hash-table :test #'equal))
  ;; fact -> list of justifications that mention it as an antecedent (reverse deps)
  (revdeps (make-hash-table :test #'equal)))

(defstruct node
  fact
  (in? nil)
  (assumption? nil)
  (justs '()))  ; list of justification ids or objects

(defstruct justification
  id
  name
  antecedents   ; list of facts
  consequents)  ; list of facts

(defun jtms-get-node (tms fact)
  (or (gethash fact (jtms-nodes tms))
      (setf (gethash fact (jtms-nodes tms))
            (make-node :fact fact))))

(defun jtms-node-in? (tms fact)
  (node-in? (jtms-get-node tms fact)))
```

---

## 4) Support indexing + add/remove justifications — `support.lisp`

We need:
- add justification
- maintain reverse dependency index (antecedent → justifications)
- remove justification if needed (optional; you can keep and mark stale)

```lisp
(in-package #:textquest.reasoning)

(defvar *just-id* 0)

(defun %new-just-id () (incf *just-id*))

(defun jtms-add-justification! (tms name antecedents consequents)
  (let* ((jid (%new-just-id))
         (j (make-justification :id jid :name name
                                :antecedents antecedents
                                :consequents consequents)))
    ;; attach to consequents
    (dolist (c consequents)
      (push j (node-justs (jtms-get-node tms c))))
    ;; reverse deps: antecedent -> justifications
    (dolist (a antecedents)
      (push j (gethash a (jtms-revdeps tms))))
    j))
```

---

## 5) Belief maintenance: propagate IN/OUT — `jtms.lisp`

A node is IN if:
- it’s an assumption **and present in DB**, OR
- it has at least one justification whose antecedents are all IN

We’ll implement:
- `jtms-assume!` for user/base facts
- `jtms-unassume!`
- `jtms-recompute!` to propagate changes starting from affected facts

```lisp
(in-package #:textquest.reasoning)

(defun jtms-supported-by-any-just? (tms fact)
  (let* ((n (jtms-get-node tms fact))
         (js (node-justs n)))
    (some (lambda (j)
            (every (lambda (a) (jtms-node-in? tms a))
                   (justification-antecedents j)))
          js)))

(defun jtms-should-be-in? (tms fact)
  (let ((n (jtms-get-node tms fact)))
    (or (node-assumption? n)
        (jtms-supported-by-any-just? tms fact))))

(defun jtms-set-in! (tms fact in?)
  (let ((n (jtms-get-node tms fact)))
    (setf (node-in? n) in?)
    in?))

(defun jtms-assume! (tms fact)
  (let ((n (jtms-get-node tms fact)))
    (setf (node-assumption? n) t
          (node-in? n) t)
    t))

(defun jtms-unassume! (tms fact)
  (let ((n (jtms-get-node tms fact)))
    (setf (node-assumption? n) nil)
    t))

(defun jtms-affected-consequents (tms fact)
  "All consequents of justifications that have FACT as antecedent."
  (let ((out '()))
    (dolist (j (gethash fact (jtms-revdeps tms)))
      (dolist (c (justification-consequents j))
        (pushnew c out :test #'equal)))
    out))

(defun jtms-recompute! (tms changed-facts)
  "Propagate IN/OUT changes starting from CHANGED-FACTS."
  (let ((queue (copy-list changed-facts))
        (seen (make-hash-table :test #'equal))
        (changed '()))
    (labels ((enqueue (f)
               (unless (gethash f seen)
                 (setf (gethash f seen) t)
                 (push f queue))))
      (dolist (f queue) (setf (gethash f seen) t))
      (loop while queue do
        (let* ((f (pop queue))
               (was (jtms-node-in? tms f))
               (now (jtms-should-be-in? tms f)))
          (unless (eql was now)
            (jtms-set-in! tms f now)
            (push f changed)
            ;; if f flipped, its dependents might flip too
            (dolist (c (jtms-affected-consequents tms f))
              (enqueue c))))))
    (nreverse changed)))
```

---

## 6) Integration: DB ↔ JTMS — `integrate.lisp`

This is where it becomes real.

Rules:
- When you **assert a base fact** (from player input / data patch), you:
  1) assert into DB
  2) `jtms-assume!` it
  3) recompute (causing derived facts to appear)

- When you **retract a base fact**, you:
  1) retract from DB
  2) `jtms-unassume!` it
  3) recompute (causing derived facts to disappear)

- When productions fire and derive facts:
  - Instead of directly asserting derived facts as “assumptions”
  - you add a **justification** and let JTMS decide if the derived fact is IN
  - then you sync JTMS belief state to DB

### Sync helpers

```lisp
(in-package #:textquest.reasoning)

(defun db-assert! (db fact)
  (destructuring-bind (e s f) fact
    (fdb-assert! db e s f)))

(defun db-retract! (db fact)
  (destructuring-bind (e s f) fact
    (fdb-retract! db e s f)))

(defun jtms-sync-to-db! (tms db facts)
  "Given list of FACTS that may have changed belief, ensure DB matches node IN state."
  (dolist (fact facts)
    (if (jtms-node-in? tms fact)
        (db-assert! db fact)
        (db-retract! db fact))))
```

### Base edits

```lisp
(defun rms-assert-base! (tms db fact)
  (db-assert! db fact)
  (jtms-assume! tms fact)
  (jtms-sync-to-db! tms db (jtms-recompute! tms (list fact)))
  fact)

(defun rms-retract-base! (tms db fact)
  (db-retract! db fact)
  (jtms-unassume! tms fact)
  (jtms-sync-to-db! tms db (jtms-recompute! tms (list fact)))
  fact)
```

### Derived facts from productions

When a production instance fires with antecedents A and consequents C:

```lisp
(defun rms-derive! (tms db rule-name antecedents consequents)
  (jtms-add-justification! tms rule-name antecedents consequents)
  ;; derived facts may become IN immediately if antecedents are IN
  (jtms-sync-to-db! tms db (jtms-recompute! tms consequents))
  consequents)
```

---

## 7) Update your production firing to emit justifications

Right now your production system likely does `(:assert ...)` directly.

Update your action applier so:
- `:assert` inside productions becomes **derived** (a justification), not an assumption
- and the antecedents are the matched facts for that rule firing

### Minimal change pattern
When firing a production activation `(prod, env)`, you already know:
- the production name
- the `:if` patterns and which facts matched them

Modify `%matches` to return not just `env`, but also the **supporting facts** it matched (the actual triples).

Then, on fire:
- compute derived facts (substituted templates)
- call `rms-derive!` with `(supports, derived)`

If you want, I can show the exact diff for your matcher; but conceptually:

- Old: matches → list of envs
- New: matches → list of `(env . matched-facts)`

That’s the one upgrade that makes RMS work well.

---

## 8) Explanations (“why is this true?”) — `explain.lisp`

A simple explainer: find one active justification that currently supports a fact.

```lisp
(in-package #:textquest.reasoning)

(defun why (tms fact)
  (let* ((n (jtms-get-node tms fact)))
    (cond
      ((node-assumption? n) (list :assumption fact))
      ((not (node-in? n)) (list :not-believed fact))
      (t
       (let ((j (find-if (lambda (j)
                           (every (lambda (a) (jtms-node-in? tms a))
                                  (justification-antecedents j)))
                         (node-justs n))))
         (if (null j)
             (list :in-but-no-just-found fact)
             (list :because
                   :rule (justification-name j)
                   :antecedents (justification-antecedents j))))))))
```

Use at REPL:
```lisp
(textquest.reasoning:why tms '(player :can-go (north alley)))
```

---

## 9) Persistence (important for forever sim)

Persist:
- nodes: `(fact in? assumption?)`
- justifications: `(name antecedents consequents)`
- revdeps can be rebuilt on load

Store only data (no closures).

---

## 10) How this changes your live-edit workflow

Instead of calling raw `fdb-assert!`, use RMS-aware functions:

- `rms-assert-base!` for operator/admin edits
- `rms-retract-base!` for removals
- productions call `rms-derive!` for derived changes

So when you type in the interpreter:

```lisp
(rms-assert-base! tms db '(tavern :exit (north alley)))
```

JTMS will automatically (re)derive:
- `(player :can-go (north alley))` (if other supports exist)

And if you remove:
```lisp
(rms-retract-base! tms db '(tavern :exit (north alley)))
```

It will automatically retract derived facts that depended on that exit.

That’s reason maintenance.

---

## 11) One practical warning (infinite sim hygiene)

JTMS can accumulate justifications forever if you keep generating novel ones.
To keep memory bounded, add one of these policies:

- **Justification reuse**: key by `(rule-name + antecedents + consequents)` and don’t add duplicates
- **Garbage collect OUT facts**: periodically remove justifications whose consequents and antecedents are all OUT and not assumptions
- **Windowed memory**: only keep justifications from last N turns for ephemeral facts; persist only “structural” ones

If you tell me whether your derived facts are mostly **ephemeral** (per turn) or **structural** (world rules), I’ll give you the right GC strategy.

---

If you want, paste one of your current productions (a `defprod` rule) and I’ll show the exact modified firing path that captures *matched supporting facts* and calls `rms-derive!` automatically.

If by “data dependent network graph” you mean: **a graph where nodes are data (facts/frames) and edges show what data depends on what other data**, that’s exactly what you want on top of your Reason Maintenance System.

In your game, the clean definition is:

- **Node** = a fact (your triple): `(ent slot filler)`
- **Edge** = “A supports B” because a **justification / production instance** used A as an antecedent to derive B
- Optionally, also connect **entities** and **slots** as higher-level nodes (summary graph)

Below is a concrete, drop-in design that works with your JTMS and stays bounded + persistable.

---

## 1) Add a dependency-graph module

Project structure:

```
src/reasoning/rms/
  jtms.lisp
  support.lisp
  integrate.lisp
  explain.lisp
  depgraph.lisp        ; NEW: build/query/export dependency network graph
```

Exports you’ll want:
- `deps-of fact` (what this fact depends on)
- `users-of fact` (what depends on this)
- `subgraph fact depth`
- `export-dot` (Graphviz)

---

## 2) Maintain the graph incrementally from justifications

You already store justifications:

- `antecedents` (facts)
- `consequents` (facts)

That *is* the dependency graph.

### Data structure (fast queries)

- `forward`: fact → set of facts it supports (outgoing edges)
- `backward`: fact → set of facts that support it (incoming edges)
- optionally edge labels: rule name, justification id

### `src/reasoning/rms/depgraph.lisp`

```lisp
(in-package #:textquest.reasoning)

(defstruct depgraph
  ;; fact -> list of facts it supports
  (out (make-hash-table :test #'equal))
  ;; fact -> list of facts that support it
  (in  (make-hash-table :test #'equal))
  ;; (from . to) -> list of labels (rule names / justification ids)
  (labels (make-hash-table :test #'equal)))

(defun %pushnew (x lst &key (test #'equal))
  (if (member x lst :test test) lst (cons x lst)))

(defun dep-add-edge! (g from to &optional label)
  (setf (gethash from (depgraph-out g))
        (%pushnew to (gethash from (depgraph-out g)) :test #'equal))
  (setf (gethash to (depgraph-in g))
        (%pushnew from (gethash to (depgraph-in g)) :test #'equal))
  (when label
    (let* ((k (cons from to))
           (ls (gethash k (depgraph-labels g))))
      (setf (gethash k (depgraph-labels g))
            (%pushnew label ls :test #'equal))))
  t)

(defun dep-remove-edge! (g from to &optional label)
  ;; optional: if label provided, remove just that label; if no labels remain, remove edge
  (let* ((k (cons from to))
         (ls (gethash k (depgraph-labels g))))
    (when label
      (setf ls (remove label ls :test #'equal))
      (if ls
          (setf (gethash k (depgraph-labels g)) ls)
          (remhash k (depgraph-labels g))))
    ;; if no labels left for this edge, remove adjacency
    (when (or (null label) (null (gethash k (depgraph-labels g))))
      (setf (gethash from (depgraph-out g))
            (remove to (gethash from (depgraph-out g)) :test #'equal))
      (setf (gethash to (depgraph-in g))
            (remove from (gethash to (depgraph-in g)) :test #'equal))))
  t)

(defun deps-of (g fact)
  "Facts that FACT depends on (incoming neighbors)."
  (copy-list (gethash fact (depgraph-in g))))

(defun users-of (g fact)
  "Facts that depend on FACT (outgoing neighbors)."
  (copy-list (gethash fact (depgraph-out g))))

(defun edge-labels (g from to)
  (copy-list (gethash (cons from to) (depgraph-labels g))))
```

---

## 3) Hook it into JTMS justification creation

When you add a justification:

- for each antecedent `a`
- for each consequent `c`
- add edge `a -> c` labeled with rule name (or justification id)

Modify your `jtms-add-justification!` (from earlier) to also update a depgraph.

Example:

```lisp
(defun jtms-add-justification+graph! (tms g name antecedents consequents)
  (let ((j (jtms-add-justification! tms name antecedents consequents)))
    (dolist (a antecedents)
      (dolist (c consequents)
        (dep-add-edge! g a c (list :rule name :jid (justification-id j)))))
    j))
```

In your RMS integration, use this function instead of the plain one.

---

## 4) Build a “data-dependent subgraph” around a fact

This is useful for debugging: “show me everything within 2 hops of this fact”.

```lisp
(defun subgraph (g seed &key (depth 2) (direction :both))
  "Return (values nodes edges) where edges are (from to labels)."
  (let ((seen (make-hash-table :test #'equal))
        (nodes '())
        (edges '()))
    (labels ((visit (n d)
               (unless (gethash n seen)
                 (setf (gethash n seen) t)
                 (push n nodes))
               (when (> d 0)
                 (when (member direction '(:out :both))
                   (dolist (to (users-of g n))
                     (push (list n to (edge-labels g n to)) edges)
                     (visit to (1- d))))
                 (when (member direction '(:in :both))
                   (dolist (from (deps-of g n))
                     (push (list from n (edge-labels g from n)) edges)
                     (visit from (1- d)))))))
      (visit seed depth))
    (values (nreverse nodes) (nreverse edges))))
```

---

## 5) Export the graph to Graphviz DOT (so you can visualize)

```lisp
(defun fact->label (fact)
  ;; Make a compact label; adjust as you like
  (with-output-to-string (s)
    (prin1 fact s)))

(defun export-dot (g path &key (seed nil) (depth 2) (direction :both))
  (multiple-value-bind (nodes edges)
      (if seed (subgraph g seed :depth depth :direction direction)
          ;; full graph: nodes inferred from adjacency tables
          (let ((ns '()) (es '()))
            (maphash (lambda (from tos)
                       (pushnew from ns :test #'equal)
                       (dolist (to tos)
                         (pushnew to ns :test #'equal)
                         (push (list from to (edge-labels g from to)) es)))
                     (depgraph-out g))
            (values ns es)))
    (with-open-file (out path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (format out "digraph DataDeps {~%  rankdir=LR;~%  node [shape=box];~%")
      (dolist (n nodes)
        (format out "  \"~A\";~%" (fact->label n)))
      (dolist (e edges)
        (destructuring-bind (from to labels) e
          (let ((lbl (if labels
                         (with-output-to-string (s)
                           (princ (getf (first labels) :rule) s))
                         "")))
            (format out "  \"~A\" -> \"~A\" [label=\"~A\"];~%"
                    (fact->label from) (fact->label to) lbl))))
      (format out "}~%"))
    path))
```

Usage:

```lisp
(export-dot depgraph "deps.dot" :seed '(player :can-go (north alley)) :depth 3)
```

Then:

```bash
dot -Tpng deps.dot -o deps.png
```

---

## 6) Make it “data-dependent” (only include edges for *active* justifications)

In an infinite sim, you don’t want a graph that grows forever with dead edges.

Two modes:

### A) Structural graph (all justifications ever)
Good for audits, but unbounded.

### B) Active graph (only edges that currently support IN facts)
Bounded-ish if your world stabilizes.

Implementation approach:
- When exporting (or querying), only include an edge `a -> c` if there exists a justification for `c` such that:
  - `a` is in its antecedents
  - and **all antecedents are IN**
  - and `c` is currently IN

That’s “data-dependent” in the literal sense: the network changes with the data.

If you want that, I’ll tweak `subgraph`/`export-dot` to consult `tms` and filter edges.

---

## 7) Practical “what do I do with this graph?”

- **Explain**: “Why is `(player :can-go (north alley))` true?”
  - follow incoming edges to find supports
- **Impact analysis**: “If I remove this exit, what breaks?”
  - traverse outgoing edges from `(tavern :exit (north alley))`
- **Debug patches**: after live edits, visualize the local subgraph to see unexpected dependencies

---

## 8) Where to store it

Add to your game state:

- `game.tms` (JTMS)
- `game.depgraph` (dependency graph)

And when productions fire and call `rms-derive!`, you update both in the same place.

---

If you answer one thing, I can lock it in: do you want the dependency graph at the level of **facts only** `(ent slot filler)` (recommended), or also a **higher-level entity graph** (entities as nodes; edges when any fact about A influences any fact about B)?

Here’s an updated **project structure** that cleanly incorporates what you’ve already got **plus** the newer pieces we discussed: **calendar**, **infinite sim loop**, **rolling checkpoints/snapshots**, **chronological backtracking (trail)**, **coroutines + agendas**, and a **data-dependent dependency graph** on top of your **RMS/JTMS**.

I’m keeping your existing files where possible and only adding/organizing what’s missing.

---

## Updated structure (proposed)

```
textquest/
  README.md
  LICENSE                      ; optional but recommended
  .gitignore
  directory_outline.txt
  textquest.asd
  textquest-tests.asd

  test/
    core-test.lisp
    reasoning-test.lisp
    calendar-test.lisp
    sim-test.lisp

  src/
    build.lisp
    main.lisp
    packages.lisp              ; (add if missing) central defpackage

    core/
      util.lisp
      errors.lisp
      log.lisp

      time.lisp                ; existing (turn clock / tick counters)
      agenda.lisp              ; existing (core scheduler)
      coro.lisp                ; existing (coroutines)

      ring.lisp                ; NEW: ring buffer for rolling history
      trail.lisp               ; NEW: reversible ops for chronological backtracking
      snapshot.lisp            ; NEW: snapshot helpers (data-only)

    sim/
      loop.lisp                ; NEW: forever simulation tick loop
      checkpoint.lisp          ; NEW: rolling checkpoint policy (keep last N)
      events.lisp              ; NEW: optional event log (append-only)
      metrics.lisp             ; NEW: sim health, counters, drift checks

    calendar/
      datetime.lisp            ; NEW: dt struct + comparisons + date math
      clock.lisp               ; NEW: sim-clock (now + advance)
      schedule.lisp            ; NEW: recurrence (daily/weekly/monthly)
      calendar.lisp            ; NEW: calendar event store + pop/fire
      integration.lisp         ; NEW: fire events into WM (facts)
      persist.lisp             ; NEW: serialize/restore calendar state
      view.lisp                ; NEW: optional month view / debugging print

    io/
      save.lisp                ; existing (extend to include calendar/sim/rms)
      paths.lisp               ; NEW: macOS app-support paths, installed assets
      patch.lisp               ; NEW: apply patch ops (:assert/:retract/:set/:ensure)
      export.lisp              ; NEW: export DOT / reports / debug dumps

    content/
      loader.lisp              ; NEW: load assets/bio/*.sexp + worlds + patches
      registry.lisp            ; NEW: registries for scripts/coroutines by name
      schema.lisp              ; NEW: schema/data version + migrations

    game/
      state.lisp               ; existing (add clock/calendar/sim state fields)
      world.lisp               ; existing
      actions.lisp             ; existing
      rules.lisp               ; existing

      undo.lisp                ; NEW: user undo + rewind within window
      reconcile.lisp           ; NEW: reconcile content updates into state

    reasoning/
      frames.lisp              ; existing (make reversible via trail if enabled)
      wm.lisp                  ; existing

      productions.lisp         ; existing (update to output supports for RMS)
      conflict.lisp            ; existing
      fire.lisp                ; NEW: agenda/refraction firing loop (if not already)
      retrieve.lisp            ; existing
      kb.lisp                  ; existing (optional; keep if you use it)

      rms/
        jtms.lisp              ; existing
        support.lisp           ; existing
        integrate.lisp         ; existing
        persist.lisp           ; existing
        explain.lisp           ; NEW: why/why-not
        depgraph.lisp          ; NEW: data-dependent dependency graph
        gc.lisp                ; NEW: prune old justifications (infinite sim hygiene)

    biology/
      bio-core.lisp            ; NEW: organisms/populations frames conventions
      physiology.lisp          ; NEW: metabolism, energy, hydration (slow updates)
      lifecycle.lisp           ; NEW: aging/birth/death
      disease.lisp             ; NEW: infection/immunity
      ecology.lisp             ; NEW: population dynamics
      bio-calendar.lisp        ; NEW: seasonal/circadian hooks via calendar
      bio-persist.lisp         ; NEW: persist biology-specific caches if any

    dsl/
      dsl-packages.lisp
      macros.lisp
      compile.lisp

    console/
      admin.lisp               ; REPL helpers: add/rm/set, patch recording, etc.
      repl.lisp                ; NEW: dev loader that binds *game* and starts sim

    scripts/
      build.py                 ; existing
      package_macos_pkg.py     ; NEW: build pkgroot + pkgbuild/productbuild
      dev.py                   ; NEW: build+run+repl convenience
      run.lisp                 ; NEW: quick load/run script (sbcl --load)

  assets/
    bio/
      species.sexp
      pathogens.sexp
      nutrients.sexp
      patches/
        0003_add_reptiles.sexp
        0004_tune_flu_params.sexp

    worlds/
    players/
    saves/
```

---

## What changed vs your current tree (high impact)

### Added
- `src/sim/` — your “runs forever” control plane (tick loop, checkpoints, events)
- `src/calendar/` — in-sim calendar + recurrence + integration
- `src/core/trail.lisp` + `ring.lisp` + `snapshot.lisp` — bounded undo/backtrack + rolling history
- `src/reasoning/rms/depgraph.lisp` — data-dependent dependency network graph
- `src/reasoning/rms/explain.lisp` — `why` explanations
- `src/reasoning/rms/gc.lisp` — keep JTMS bounded in an infinite sim
- `src/io/patch.lisp` + `src/content/schema.lisp` — live updates with migrations
- `src/biology/` — biology as a subsystem driven by calendar/agenda
- `scripts/package_macos_pkg.py` — mac pkg installer build

### Slight reorg
- `assets` belongs at repo root (yours currently sits under `src/assets`). In the proposal, `assets/` is top-level.  
  If you *must* keep it under `src/`, it still works—just adjust path resolution in `io/paths.lisp`.

---

## Minimal “diff” version (if you don’t want a big move)
If you want the smallest change that still adds what you asked for, add only:

- `src/core/trail.lisp`
- `src/core/ring.lisp`
- `src/sim/loop.lisp`
- `src/calendar/*`
- `src/reasoning/rms/depgraph.lisp`
- `src/reasoning/rms/explain.lisp`
- `src/io/patch.lisp`
- `src/content/schema.lisp`

Everything else can come later.

---

## One important fix to make RMS + depgraph actually work
Your productions need to produce **supports** (the matched facts) when they fire, so `rms-derive!` can add justifications and depgraph edges.

So: update `reasoning/productions.lisp` matcher to return:
- `env`
- `matched-facts` (the actual triples that satisfied each IF pattern)

Then `rms/integrate.lisp` can do:
- `jtms-add-justification!`
- `dep-add-edge!` for each antecedent→consequent

---

If you want, I can also rewrite your `textquest.asd` component list to match this structure (serial order that loads cleanly), but the tree above is the correct updated layout given everything you’ve built and the features you’ve requested.

