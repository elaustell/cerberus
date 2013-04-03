(* generated by Ott 0.21.2 from: Common_.ott *)
Require Relations.
Require Import List.
Require Import Bool.
Require Import ZArith.
Require Import Program.

Open Scope type.

Definition neg P := P -> False.
Definition boolSpec (b : bool) p := if b then p else neg p.

Lemma boolSpec_true {p} : boolSpec true p = p.
Proof. reflexivity. Defined.

Lemma boolSpec_false {p} : boolSpec false p = neg p.
Proof. reflexivity. Defined.

Ltac boolSpec_destruct :=
  match goal with
  | [ H : boolSpec ?b _ |- _] =>
      match b with
      | true  => fail 1
      | false => fail 1
      | _     =>
          let Heq := fresh in
          case_eq b; intros Heq; rewrite Heq in *; clear Heq; simpl in H
      end
  end.

Ltac or_destruct :=
  match goal with
  | [|- _ \/ _ -> _] =>
      let Heq := fresh in
      intros [Heq|Heq]; revert Heq
  | [|- _ -> _] =>
      let Heq := fresh in
      intros Heq; or_destruct; revert Heq
  end.

Ltac and_destruct :=
  match goal with
  | [|- _ /\ _ -> _] =>
      apply and_rect
  | [|- _ -> _] =>
      let Heq := fresh in
      intros Heq; and_destruct; revert Heq
  end.

Ltac bool_simpl :=
  repeat match goal with
  | [|- context[_ || _ = true]] =>
      rewrite orb_true_iff; or_destruct
  | [|- context[_ || _ = false]] =>
      rewrite orb_false_iff; and_destruct
  | [|- context[_ && _ = true]] =>
      rewrite andb_true_iff; and_destruct
  | [|- context[_ && _ = false]] =>
      rewrite andb_false_iff; or_destruct
  | [|- context[negb _ = true ]] =>
      rewrite negb_true_iff
  | [|- context[negb _ = false]] =>
      rewrite negb_false_iff
  end.

Ltac boolSpec_simpl :=
  repeat match goal with
  | [H : boolSpec ?B _ |- ?B = _ -> _] =>
      let Heq := fresh in
      intros Heq; rewrite Heq in H
  | [H : boolSpec ?B _ |- _] =>
      match B with
      | true  => rewrite boolSpec_true  in H
      | false => rewrite boolSpec_false in H
      | _     => let b := fresh in
                 progress (set B as b in H; simpl in b; subst b)
      end
  end.

Definition decidable P := P + neg P.
Class Decision (P : Type) := decision : decidable P.

Definition boolSpec_Decision {b : bool} {P : Type} (B : boolSpec b P) : Decision P.
Proof. destruct b; [left | right]; assumption. Defined.
Definition boolSpec_elim1 {b : bool} {P : Type} : boolSpec b P -> b = true -> P.
Proof. intros; subst; assumption. Defined.
Definition boolSpec_elim2 {b : bool} {P : Type} : boolSpec b P -> b = false -> neg P.
Proof. intros; subst; assumption. Defined.
Definition boolSpec_elim1_inv {b : bool} {P : Type} : boolSpec b P -> P -> b = true.
Proof. destruct b; solve [reflexivity | contradiction]. Defined.
Definition boolSpec_elim2_inv {b : bool} {P : Type} : boolSpec b P -> neg P -> b = false.
Proof. destruct b; solve [reflexivity | contradiction]. Defined.
Lemma boolSpec_elim {b : bool} {P : Prop} : boolSpec b P -> (P <-> b = true).
Proof. intros B; generalize (boolSpec_elim1 B), (boolSpec_elim1_inv B); tauto. Defined.

Definition bool_of_decision {P} : Decision P -> bool :=
  fun d => match d with
           | inl _ => true
           | inr _ => false
           end.

Definition relation A := A -> A -> Type.
Definition complement {A} (R : relation A) x y := neg (R x y).
Class Reflexive {A} (R : relation A) :=
  reflexive x : R x x.
Class Irreflexive {A} (R : relation A) :=
  irreflexive : Reflexive (complement R).
Class Asymmetric {A} (R : relation A) :=
  asymmetric x y : R x y -> R y x -> False.

Class DecidableRelation {A} (R : Relation_Definitions.relation A) :=
  decide : forall x y : A, Decision (R x y).
Class DecidableEq (A : Type) :=
  Decidable_Equality :> DecidableRelation (@eq A).

Ltac finish t := solve [ congruence | discriminate | reflexivity | t
                       | econstructor (solve [eauto])
                       | intros; inversion 1; solve [contradiction | congruence | discriminate]
                       | inversion 1; solve [contradiction | congruence | discriminate] 
                       ].
Ltac decide_destruct :=
  match goal with
  | [ |- context[match ?d with _ => _ end] ] =>
      match type of d with
      | bool => (
          let H := fresh "H" in
          assert {H : bool & d = H};
          [ exists d; reflexivity 
          | destruct H as [H Heq];
            replace d with H;
            destruct H;
            revert Heq ]
          ) || fail 1
      | _ => destruct d
      end
  | [ |- context[decide ?a ?b] ] => destruct (decide a b)
  | [ |- ?a = ?a -> _] => intros _
  end.
Ltac scatter d := subst; simpl; first [d | decide_destruct].
Ltac finish_scatter_loop f d := repeat (first [finish f | scatter d | constructor]).
Ltac my_auto' f d := repeat (subst; simpl; auto; try (now finish_scatter_loop f d); try scatter d).
Ltac my_auto := my_auto' fail fail.
Obligation Tactic := my_auto.

Definition Decision_elim {P} {A} : Decision P -> (P -> A) -> (neg P -> A) -> A :=
  fun d pos neg =>
    match d with
    | inl P => pos P
    | inr N => neg N
    end.

Ltac destruct_decide :=
  match goal with
  | [ |- context[decide ?a ?b] ] => destruct (decide a b)
  end.

Lemma decision_sumbool {P : Prop} : Decision P -> {P} + {~P}.
Proof. destruct 1; auto. Defined.

Lemma decision_sumbool_inv {P : Prop} : {P} + {~P} -> Decision P.
Proof. destruct 1; [left | right]; auto. Defined.

Lemma decidableRelation_sumbool {A} {R : Relation_Definitions.relation A} : DecidableRelation R -> forall x y, {R x y} + {~R x y}.
Proof. intros dec_R. intros x y. destruct (dec_R x y); auto. Defined.

Lemma decidableRelation_sumbool_inv {A} {R : Relation_Definitions.relation A} : (forall x y, {R x y} + {~R x y}) -> DecidableRelation R.
Proof. intros sum_R. intros x y. destruct (sum_R x y); [left | right]; auto. Defined.

Definition decidableEq_sumbool {A} : DecidableEq A -> (forall x y : A, {x = y} + {x <> y}) := decidableRelation_sumbool.
Definition decidableEq_sumbool_inv {A} : (forall x y : A, {x = y} + {x <> y}) -> DecidableEq A := decidableRelation_sumbool_inv.

Program Instance makeDecidableRelation {A} {R : Relation_Definitions.relation A} `{d : forall x y : A, Decision (R x y)} : DecidableRelation R.
Program Instance makeDecidableEq       {A}                  `{d : forall x y : A, Decision (x = y)} : DecidableEq A.

Ltac decision_eq :=
  match goal with [ |- Decision (eq ?a ?b) ] =>
    match a with appcontext C1 [?c ?t1] =>
    match b with appcontext C2 [ c ?t2] =>
      let H := fresh in
      assert (Decision (t1 = t2)) as H by apply decide;
      destruct H;
      [subst | right; inversion 1; contradiction]
    end end
  end.

Ltac decision_eq_destruct :=
  match goal with [ |- forall x y, _] =>
    destruct x; destruct y; try solve [left; reflexivity | right; inversion 1]
  end.

Ltac notHyp P :=
  match goal with
  | [ _ : P |- _ ] => fail 1
  | _ => idtac
  end.

Ltac decision_eq_fix :=
  match goal with
  | [|- forall x y :?A, _] =>
      notHyp (forall x y : A, Decision (x = y));
      let IH := fresh in
      fix IH 1
  | _ => idtac
  end.

Ltac decidable_eq :=
  match goal with
  | [ |- DecidableEq ?A] =>
    cut (forall x y : A, Decision (x = y)); [now trivial|]
  | [ |- Decision (?x = ?y)] =>
    revert x y
  | [ |- forall x y : ?A, Decision (x = y)] =>
    idtac
  end.

Ltac dec_eq :=
  decidable_eq;
  decision_eq_fix;
  decision_eq_destruct;
  repeat decision_eq;
  left; reflexivity.

Instance bool_DecEq : DecidableEq bool.
Proof. dec_eq. Defined.

Instance list_DecEq {A} `{dec_A : DecidableEq A} : DecidableEq (list A).
Proof. dec_eq. Defined.

Instance pair_DecEq {A B : Type} `{dec_A : DecidableEq A} `{dec_B : DecidableEq B} : DecidableEq (A * B).
Proof. dec_eq. Defined. 

Instance option_DecEq {A : Type} (dec_A : DecidableEq A) : DecidableEq (option A).
Proof. dec_eq. Defined. 

Require Import RelationClasses.

Class Trichotomous {A} (R: Relation_Definitions.relation A) := {
  trichotomous : forall x y : A, {R x y} + {R y x} + {x = y}
}.

Class StrictTotalOrder {A} (R : Relation_Definitions.relation A) := {
  strict_STO       :> StrictOrder R ;
  trichotomous_STO :> Trichotomous R
}.

Ltac hyp H :=
  match goal with
  | [ H : _ |- _ ] => idtac
  | _ => fail 1
  end.

Ltac unfold_goal :=
  match goal with
  | [ |- appcontext[?d] ] =>
      unfold d
  end.

Ltac destruct_sum :=
  repeat match goal with
  | [ H : sum _ _ |- _          ] => destruct H
  | [             |- _ + _ -> _ ] => destruct 1
  end.

Ltac apply_ctx :=
  match goal with
  | [ f : _ -> ?t |- ?t ] => apply f
  end.

Fixpoint list_in_fun {A:Type} (eq : A -> A -> bool) (a : A) (ls : list A) : bool :=
  match ls with
  | nil   => false
  | x::xs => orb (eq x a) (list_in_fun eq a xs)
  end.

Fixpoint list_in_fun_correct {A:Type} {eq : A -> A -> bool} (a : A) (ls : list A) :
  (forall x y, boolSpec (eq x y) (x = y)) ->
  boolSpec (list_in_fun eq a ls) (List.In a ls).
Proof.
  intros eq_correct.
  do 2 unfold_goal.
  destruct ls;
  my_auto;
  fold (@list_in_fun A);
  bool_simpl;
  repeat (match goal with
  | [|- context[eq ?x a]] =>
      notHyp (x = a); notHyp (neg (x = a));
      set (eq_correct x a)
  | [|- context[list_in_fun eq a ?ls]] =>
      notHyp (In a ls); notHyp (neg (In a ls));
      set (list_in_fun_correct A eq a ls eq_correct)      
  end; boolSpec_simpl);
  my_auto.
Qed.

Fixpoint list_forall_fun {A:Type} (dec : A -> bool) (ls : list A) : bool :=
  match ls with
  | []    => true
  | x::xs => andb (dec x) (list_forall_fun dec xs)
  end.

Fixpoint list_forall_fun_correct {A} {P : A -> Prop} {dec} ls :
  (forall a, boolSpec (dec a) (P a)) ->
  boolSpec (list_forall_fun dec ls) (Forall P ls).
Proof.
  intros dec_correct.
  do 2 unfold_goal.
  destruct ls;
  my_auto;
  fold (@list_forall_fun A);
  bool_simpl;
  repeat (match goal with
  | [|- context[dec ?a]] =>
      notHyp (P a); notHyp (neg (P a));
      set (dec_correct a)
  | [|- context[list_forall_fun dec ?ls]] =>
      notHyp (Forall P ls); notHyp (neg (Forall P ls));
      set (list_forall_fun_correct A P dec ls dec_correct)      
  end; boolSpec_simpl);
  my_auto.
Defined.

Definition sub {A} (l1 l2 : list A) :=
  List.Forall (fun x => List.In x l1) l2.

Definition list_sub_fun {A} (eq : A -> A -> bool) (l1 l2 : list A) :=
  list_forall_fun (fun x => list_in_fun eq x l1) l2.

Lemma list_sub_fun_correct  {A} {eq : A -> A -> bool} (l1 l2 : list A) :
  (forall x y, boolSpec (eq x y) (x = y)) ->
  boolSpec (list_sub_fun eq l1 l2) (sub l1 l2).
Proof.
  intros eq_correct.
  set (fun x => list_in_fun_correct x l1 eq_correct) as in_correct.
  exact (list_forall_fun_correct l2 in_correct).
Defined.

Lemma Zeqb_correct x y : boolSpec (Z.eqb x y) (x = y).
Proof.
  case_eq (Z.eqb x y); intros Heq.
  + exact (proj1 (Z.eqb_eq  _ _) Heq).
  + exact (proj1 (Z.eqb_neq _ _) Heq).
Qed.

Lemma Zltb_correct x y : boolSpec (Z.ltb x y) (x < y)%Z.
Proof.
  case_eq (Z.ltb x y); intros Heq.
  + exact (proj1 (Z.ltb_lt  _ _) Heq).
  + exact (proj1 (Z.ltb_nlt _ _) Heq).
Qed.

Lemma Decision_boolSpec {P} (D : Decision P) : boolSpec (bool_of_decision D) P.
Proof. destruct D; assumption. Qed.

Ltac var_destruct_inner c :=
  match c with
  | _ => is_var c; destruct c; try finish fail
  | match ?c with _ => _ end => var_destruct_inner c
  end.

Ltac var_destruct :=
  match goal with
  | [|- match ?c with _ => _ end] =>
      var_destruct_inner c
  end.

Ltac not_var H :=
  match goal with
  | _ => is_var H; fail 1
  | _ => idtac
  end.

Ltac pull_out T c :=
  ( let H   := fresh in
    let t   := fresh in
    let Heq := fresh in
    assert {t : T & c = t} as H by (exists c; reflexivity);
    destruct H as [t Heq];
    replace c with t;
    revert Heq
  ) || fail 1.

Ltac context_destruct_inner c :=
  match c with
  | _                        =>
      is_var c; destruct c; try finish fail
  | match ?c with _ => _ end =>
      context_destruct_inner c
  | _ =>
      match type of c with
      | bool      => pull_out bool c
      | option ?A => pull_out (option A) c
      end
  end.

Ltac context_destruct :=
  match goal with
  | [|- match ?c with _ => _ end] =>
      context_destruct_inner c
  | [|- ((match ?c with _ => _ end) = _) -> _] =>
      context_destruct_inner c
  | [|- (match ?c with _ => _ end) -> _] =>
      context_destruct_inner c
  end.

Ltac case_fun G :=
  match goal with
  | [|- _ = ?o -> _] =>
      let Heq := fresh in
      is_var o; destruct o;
      intros Heq;
      generalize G;
      rewrite Heq;
      intros ?
  end.

Ltac case_fun_hyp G :=
  match goal with
  | [|- _ = ?o -> _] =>
      let Heq := fresh in
      is_var o;
      destruct o;
      intros Heq;
      revert G;
      rewrite Heq;
      intros G
  end.

Ltac case_fun_destruct :=
  match goal with
  | [|- ?t = ?o -> _] =>
      let Heq := fresh in
      is_var o; destruct t; intros Heq; rewrite <- Heq; clear Heq
  end.

Ltac context_destruct_all :=
  repeat (context_destruct; try case_fun_destruct).
