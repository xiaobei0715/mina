open Core
open Mina_base
open Snark_params
module Global_slot = Mina_numbers.Global_slot
open Currency

let top_hash_logging_enabled = ref false

module Wire_types = Mina_wire_types.Mina_state.Snarked_ledger_state

module Make_sig (A : Wire_types.Types.S) = struct
  module type S =
    Snarked_ledger_state_intf.Full
      with type ( 'ledger_hash
                , 'amount
                , 'pending_coinbase
                , 'fee_excess
                , 'sok_digest
                , 'local_state
                , 'bool )
                Poly.Stable.V2.t =
        ( 'ledger_hash
        , 'amount
        , 'pending_coinbase
        , 'fee_excess
        , 'sok_digest
        , 'local_state
        , 'bool )
        A.Poly.V2.t
       and type Stable.V2.t = A.V2.t
       and type With_sok.Stable.V2.t = A.With_sok.V2.t
end

module Make_str (A : Wire_types.Concrete) = struct
  module Pending_coinbase_stack_state = struct
    module Init_stack = struct
      [%%versioned
      module Stable = struct
        module V1 = struct
          type t =
            | Base of Pending_coinbase.Stack_versioned.Stable.V1.t
            | Merge
          [@@deriving sexp, hash, compare, equal, yojson]

          let to_latest = Fn.id
        end
      end]
    end

    module Poly = struct
      [%%versioned
      module Stable = struct
        module V1 = struct
          type 'pending_coinbase t =
            { source : 'pending_coinbase; target : 'pending_coinbase }
          [@@deriving sexp, hash, compare, equal, fields, yojson, hlist]

          let to_latest pending_coinbase { source; target } =
            { source = pending_coinbase source
            ; target = pending_coinbase target
            }
        end
      end]

      let typ pending_coinbase =
        Tick.Typ.of_hlistable
          [ pending_coinbase; pending_coinbase ]
          ~var_to_hlist:to_hlist ~var_of_hlist:of_hlist ~value_to_hlist:to_hlist
          ~value_of_hlist:of_hlist
    end

    type 'pending_coinbase poly = 'pending_coinbase Poly.t =
      { source : 'pending_coinbase; target : 'pending_coinbase }
    [@@deriving sexp, hash, compare, equal, fields, yojson]

    (* State of the coinbase stack for the current transaction snark *)
    [%%versioned
    module Stable = struct
      module V1 = struct
        type t = Pending_coinbase.Stack_versioned.Stable.V1.t Poly.Stable.V1.t
        [@@deriving sexp, hash, compare, equal, yojson]

        let to_latest = Fn.id
      end
    end]

    type var = Pending_coinbase.Stack.var Poly.t

    let typ = Poly.typ Pending_coinbase.Stack.typ

    let to_input ({ source; target } : t) =
      Random_oracle.Input.Chunked.append
        (Pending_coinbase.Stack.to_input source)
        (Pending_coinbase.Stack.to_input target)

    let var_to_input ({ source; target } : var) =
      Random_oracle.Input.Chunked.append
        (Pending_coinbase.Stack.var_to_input source)
        (Pending_coinbase.Stack.var_to_input target)

    include Hashable.Make_binable (Stable.Latest)
    include Comparable.Make (Stable.Latest)
  end

  module Poly = struct
    [%%versioned
    module Stable = struct
      module V2 = struct
        type ( 'ledger_hash
             , 'amount
             , 'pending_coinbase
             , 'fee_excess
             , 'sok_digest
             , 'local_state
             , 'bool )
             t =
              ( 'ledger_hash
              , 'amount
              , 'pending_coinbase
              , 'fee_excess
              , 'sok_digest
              , 'local_state
              , 'bool )
              A.Poly.V2.t =
          { source :
              ( 'ledger_hash
              , 'pending_coinbase
              , 'local_state )
              Registers.Stable.V1.t
          ; target :
              ( 'ledger_hash
              , 'pending_coinbase
              , 'local_state )
              Registers.Stable.V1.t
          ; connecting_ledger_left : 'ledger_hash
          ; connecting_ledger_right : 'ledger_hash
          ; supply_increase : 'amount
          ; fee_excess : 'fee_excess
          ; zkapp_updates_applied : 'bool
          ; sok_digest : 'sok_digest
          }
        [@@deriving compare, equal, hash, sexp, yojson, hlist]
      end
    end]

    let with_empty_local_state ~supply_increase ~fee_excess ~sok_digest
        ~source_first_pass_ledger ~target_first_pass_ledger
        ~source_second_pass_ledger ~target_second_pass_ledger
        ~connecting_ledger_left ~connecting_ledger_right
        ~pending_coinbase_stack_state ~zkapp_updates_applied : _ t =
      { supply_increase
      ; fee_excess
      ; sok_digest
      ; zkapp_updates_applied
      ; connecting_ledger_left
      ; connecting_ledger_right
      ; source =
          { first_pass_ledger = source_first_pass_ledger
          ; second_pass_ledger = source_second_pass_ledger
          ; pending_coinbase_stack =
              pending_coinbase_stack_state.Pending_coinbase_stack_state.source
          ; local_state = Local_state.empty ()
          }
      ; target =
          { first_pass_ledger = target_first_pass_ledger
          ; second_pass_ledger = target_second_pass_ledger
          ; pending_coinbase_stack = pending_coinbase_stack_state.target
          ; local_state = Local_state.empty ()
          }
      }

    let typ ledger_hash amount pending_coinbase fee_excess sok_digest
        local_state_typ zkapp_updates_applied =
      let registers =
        let open Registers in
        Tick.Typ.of_hlistable
          [ ledger_hash; ledger_hash; pending_coinbase; local_state_typ ]
          ~var_to_hlist:to_hlist ~var_of_hlist:of_hlist ~value_to_hlist:to_hlist
          ~value_of_hlist:of_hlist
      in
      Tick.Typ.of_hlistable
        [ registers
        ; registers
        ; ledger_hash
        ; ledger_hash
        ; amount
        ; fee_excess
        ; zkapp_updates_applied
        ; sok_digest
        ]
        ~var_to_hlist:to_hlist ~var_of_hlist:of_hlist ~value_to_hlist:to_hlist
        ~value_of_hlist:of_hlist
  end

  [%%versioned
  module Stable = struct
    module V2 = struct
      type t =
        ( Frozen_ledger_hash.Stable.V1.t
        , (Amount.Stable.V1.t, Sgn.Stable.V1.t) Signed_poly.Stable.V1.t
        , Pending_coinbase.Stack_versioned.Stable.V1.t
        , Fee_excess.Stable.V1.t
        , unit
        , Local_state.Stable.V1.t
        , bool )
        Poly.Stable.V2.t
      [@@deriving compare, equal, hash, sexp, yojson]

      let to_latest = Fn.id
    end
  end]

  type var =
    ( Frozen_ledger_hash.var
    , Currency.Amount.Signed.var
    , Pending_coinbase.Stack.var
    , Fee_excess.var
    , unit
    , Local_state.Checked.t
    , Tick.Boolean.var )
    Poly.t

  let typ : (var, t) Tick.Typ.t =
    Poly.typ Frozen_ledger_hash.typ Currency.Amount.Signed.typ
      Pending_coinbase.Stack.typ Fee_excess.typ Tick.Typ.unit Local_state.typ
      Tick.Boolean.typ

  module With_sok = struct
    [%%versioned
    module Stable = struct
      module V2 = struct
        type t =
          ( Frozen_ledger_hash.Stable.V1.t
          , (Amount.Stable.V1.t, Sgn.Stable.V1.t) Signed_poly.Stable.V1.t
          , Pending_coinbase.Stack_versioned.Stable.V1.t
          , Fee_excess.Stable.V1.t
          , Sok_message.Digest.Stable.V1.t
          , Local_state.Stable.V1.t
          , bool )
          Poly.Stable.V2.t
        [@@deriving compare, equal, hash, sexp, yojson]

        let to_latest = Fn.id
      end
    end]

    type display =
      (string, string, string, int, string, Local_state.display, bool) Poly.t

    let display _ = failwith "TODO"

    let genesis ~genesis_ledger_hash : t =
      let registers =
        { Registers.first_pass_ledger = genesis_ledger_hash
        ; second_pass_ledger = genesis_ledger_hash
        ; pending_coinbase_stack = Pending_coinbase.Stack.empty
        ; local_state = Local_state.dummy ()
        }
      in
      { source = registers
      ; target = registers
      ; connecting_ledger_left = Frozen_ledger_hash.empty_hash
      ; connecting_ledger_right = Frozen_ledger_hash.empty_hash
      ; supply_increase = Currency.Amount.Signed.zero
      ; fee_excess = Fee_excess.empty
      ; sok_digest = Sok_message.Digest.default
      ; zkapp_updates_applied = false
      }

    type var =
      ( Frozen_ledger_hash.var
      , Currency.Amount.Signed.var
      , Pending_coinbase.Stack.var
      , Fee_excess.var
      , Sok_message.Digest.Checked.t
      , Local_state.Checked.t
      , Tick.Boolean.var )
      Poly.t

    let typ : (var, t) Tick.Typ.t =
      Poly.typ Frozen_ledger_hash.typ Currency.Amount.Signed.typ
        Pending_coinbase.Stack.typ Fee_excess.typ Sok_message.Digest.typ
        Local_state.typ Tick.Boolean.typ

    let to_input
        ({ source
         ; target
         ; connecting_ledger_left
         ; connecting_ledger_right
         ; supply_increase
         ; fee_excess
         ; sok_digest
         ; zkapp_updates_applied
         } :
          t ) =
      let input =
        Array.reduce_exn ~f:Random_oracle.Input.Chunked.append
          [| Sok_message.Digest.to_input sok_digest
           ; Registers.to_input source
           ; Registers.to_input target
           ; Frozen_ledger_hash.to_input connecting_ledger_left
           ; Frozen_ledger_hash.to_input connecting_ledger_right
           ; Amount.Signed.to_input supply_increase
           ; Fee_excess.to_input fee_excess
           ; Random_oracle.Input.Chunked.packed
               (Mina_base.Util.field_of_bool zkapp_updates_applied, 1)
          |]
      in
      if !top_hash_logging_enabled then
        Format.eprintf
          !"Generating unchecked top hash from:@.%{sexp: Tick.Field.t \
            Random_oracle.Input.Chunked.t}@."
          input ;
      input

    let to_field_elements t = Random_oracle.pack_input (to_input t)

    module Checked = struct
      type t = var

      let to_input
          ({ source
           ; target
           ; connecting_ledger_left
           ; connecting_ledger_right
           ; supply_increase
           ; fee_excess
           ; sok_digest
           ; zkapp_updates_applied
           } :
            t ) =
        let open Tick in
        let open Checked.Let_syntax in
        let%bind fee_excess = Fee_excess.to_input_checked fee_excess in
        let source = Registers.Checked.to_input source
        and target = Registers.Checked.to_input target in
        let%bind supply_increase =
          Amount.Signed.Checked.to_input supply_increase
        in
        let input =
          Array.reduce_exn ~f:Random_oracle.Input.Chunked.append
            [| Sok_message.Digest.Checked.to_input sok_digest
             ; source
             ; target
             ; Frozen_ledger_hash.var_to_input connecting_ledger_left
             ; Frozen_ledger_hash.var_to_input connecting_ledger_right
             ; supply_increase
             ; fee_excess
             ; Random_oracle.Input.Chunked.packed
                 ((zkapp_updates_applied :> Tick.Field.Var.t), 1)
            |]
        in
        let%map () =
          as_prover
            As_prover.(
              if !top_hash_logging_enabled then
                let%map input = Random_oracle.read_typ' input in
                Format.eprintf
                  !"Generating checked top hash from:@.%{sexp: Field.t \
                    Random_oracle.Input.Chunked.t}@."
                  input
              else return ())
        in
        input

      let to_field_elements t =
        let open Tick.Checked.Let_syntax in
        Tick.Run.run_checked (to_input t >>| Random_oracle.Checked.pack_input)
    end
  end

  let option lab =
    Option.value_map ~default:(Or_error.error_string lab) ~f:(fun x -> Ok x)

  module type Ledger_hash_intf = sig
    type t

    type bool

    type error

    val if_ : bool -> then_:t -> else_:t -> t

    val all : bool list -> bool

    val equal : t -> t -> bool

    val accumulate_failures : (bool * string) list -> error
  end

  module Ledger_hash_checked :
    Ledger_hash_intf
      with type t = Frozen_ledger_hash.var
       and type error = unit Tick.Checked.t
       and type bool = Tick.Boolean.var = struct
    type t = Frozen_ledger_hash.var

    type bool = Tick.Boolean.var

    type error = unit Tick.Checked.t

    let if_ b ~then_ ~else_ =
      Tick.Run.run_checked (Frozen_ledger_hash.if_ b ~then_ ~else_)

    let all bs = Tick.(Run.run_checked (Boolean.all bs))

    let equal t t' = Tick.Run.run_checked (Frozen_ledger_hash.equal_var t t')

    let accumulate_failures _bs = Tick.Checked.return ()
  end

  module Ledger_hash_unchecked :
    Ledger_hash_intf
      with type t = Frozen_ledger_hash.t
       and type error = unit Or_error.t = struct
    type t = Frozen_ledger_hash.t

    type bool = Bool.t

    type error = unit Or_error.t

    let if_ b ~then_ ~else_ = if b then then_ else else_

    let all = List.fold ~init:true ~f:( && )

    let equal = Frozen_ledger_hash.equal

    let accumulate_failures bs =
      let constraints_failed =
        List.filter_map bs ~f:(fun (b, str) -> if b then Some str else None)
      in
      if List.is_empty constraints_failed then Ok ()
      else
        Error
          (Error.createf "Constraints failed: %s"
             (String.concat ~sep:"," constraints_failed) )
  end

  module Statement_ledgers = struct
    type 'a t =
      { first_pass_ledger_source : 'a
      ; first_pass_ledger_target : 'a
      ; second_pass_ledger_source : 'a
      ; second_pass_ledger_target : 'a
      ; connecting_ledger_left : 'a
      ; connecting_ledger_right : 'a
      }
    [@@deriving compare, equal, hash, sexp, yojson]

    let of_statement (s : _ Poly.t) : _ t =
      { first_pass_ledger_source = s.source.first_pass_ledger
      ; first_pass_ledger_target = s.target.first_pass_ledger
      ; second_pass_ledger_source = s.source.second_pass_ledger
      ; second_pass_ledger_target = s.target.second_pass_ledger
      ; connecting_ledger_left = s.connecting_ledger_left
      ; connecting_ledger_right = s.connecting_ledger_right
      }
  end

  let validate_ledgers_at_merge (type a error bool)
      (module L : Ledger_hash_intf
        with type t = a
         and type error = error
         and type bool = bool ) (s1 : a Statement_ledgers.t)
      (s2 : a Statement_ledgers.t) =
    (*Check ledgers are valid based on the rules descibed in https://github.com/MinaProtocol/mina/discussions/12000*)
    let is_same_block_at_shared_boundary =
      (*First statement ends and the second statement starts in the same block. It could be within a single scan state tree or across two scan state trees*)
      L.equal s1.connecting_ledger_right s2.connecting_ledger_left
    in
    (*Rule 1*)
    let l1 =
      L.if_ is_same_block_at_shared_boundary
        ~then_:(*first pass ledger continues*) s2.first_pass_ledger_source
        ~else_:
          (*s1's first pass ledger stops at the end of a block's transactions, check that it is equal to the start of the block's second pass ledger*)
          s1.connecting_ledger_right
    in
    let rule1 =
      "First pass ledger continues or first pass ledger connects to the same \
       block's start of the second pass ledger"
    in
    let res1 = L.equal s1.first_pass_ledger_target l1 in
    (*Rule 2*)
    (*s1's second pass ledger ends at say, block B1. s2 is in the next block, say B2*)
    let l2 =
      L.if_ is_same_block_at_shared_boundary
        ~then_:(*second pass ledger continues*) s1.second_pass_ledger_target
        ~else_:
          (*s2's second pass ledger starts where B2's first pass ledger ends*)
          s2.connecting_ledger_left
    in
    let rule2 =
      "Second pass ledger continues or second pass ledger of the statement on \
       the right connects to the same block's end of first pass ledger"
    in
    let res2 = L.equal s2.second_pass_ledger_source l2 in
    (*Rule 3*)
    let l3 =
      L.if_ is_same_block_at_shared_boundary
        ~then_:(*no-op*) s1.second_pass_ledger_target
        ~else_:
          (*s2's first pass ledger starts where B1's second pass ledger ends*)
          s2.first_pass_ledger_source
    in
    let rule3 =
      "First pass ledger of the statement on the right does not connect to the \
       second pass ledger of the statement on the left"
    in
    let res3 = L.equal s1.second_pass_ledger_target l3 in
    let failures =
      L.accumulate_failures [ (res1, rule1); (res2, rule2); (res3, rule3) ]
    in
    let res = L.all [ res1; res2; res3 ] in
    (res, failures)

  let valid_ledgers_at_merge_checked
      (s1 : Frozen_ledger_hash.var Statement_ledgers.t)
      (s2 : Frozen_ledger_hash.var Statement_ledgers.t) =
    validate_ledgers_at_merge (module Ledger_hash_checked) s1 s2 |> fst

  let valid_ledgers_at_merge_unchecked
      (s1 : Frozen_ledger_hash.t Statement_ledgers.t)
      (s2 : Frozen_ledger_hash.t Statement_ledgers.t) =
    validate_ledgers_at_merge (module Ledger_hash_unchecked) s1 s2

  let merge (s1 : _ Poly.t) (s2 : _ Poly.t) =
    let open Or_error.Let_syntax in
    let or_error_of_bool ~error b =
      if b then return ()
      else
        Error
          (Error.createf "Error merging statements left: %s right %s: %s"
             (Yojson.Safe.to_string (to_yojson s1))
             (Yojson.Safe.to_string (to_yojson s2))
             error )
    in
    (*check ledgers are connected*)
    let s1_ledger = Statement_ledgers.of_statement s1 in
    let s2_ledger = Statement_ledgers.of_statement s2 in
    let%bind () = valid_ledgers_at_merge_unchecked s1_ledger s2_ledger |> snd in
    (*Check pending coinbase stack is connected*)
    let%bind () =
      or_error_of_bool ~error:"Pending coinbase stacks are not connected"
        (Pending_coinbase.Stack.connected
           ~first:s1.target.pending_coinbase_stack
           ~second:s2.source.pending_coinbase_stack () )
    in
    (*Check local states are equal*)
    let%bind () =
      or_error_of_bool ~error:"Local states are not connected"
        (Local_state.equal s1.target.local_state s2.source.local_state)
    in
    let connecting_ledger_left = s1.connecting_ledger_left in
    let connecting_ledger_right = s2.connecting_ledger_right in
    let%map fee_excess = Fee_excess.combine s1.fee_excess s2.fee_excess
    and supply_increase =
      Currency.Amount.Signed.add s1.supply_increase s2.supply_increase
      |> option "Error adding supply_increase"
    in
    (*Ignore [zkapp_updates_applied] in merge statements since we don't care
       whether or not account updates were applied, just that the proofs are
       valid and state transition is correct*)
    let zkapp_updates_applied = true in
    ( { source = s1.source
      ; target = s2.target
      ; connecting_ledger_left
      ; connecting_ledger_right
      ; fee_excess
      ; supply_increase
      ; sok_digest = ()
      ; zkapp_updates_applied
      }
      : t )

  include Hashable.Make_binable (Stable.Latest)
  include Comparable.Make (Stable.Latest)

  let gen =
    let open Quickcheck.Generator.Let_syntax in
    let%map source = Registers.gen
    and target = Registers.gen
    and connecting_ledger_left = Frozen_ledger_hash.gen
    and connecting_ledger_right = Frozen_ledger_hash.gen
    and fee_excess = Fee_excess.gen
    and supply_increase = Currency.Amount.Signed.gen
    and zkapp_updates_applied = Quickcheck.Generator.bool in
    ( { source
      ; target
      ; connecting_ledger_left
      ; connecting_ledger_right
      ; fee_excess
      ; supply_increase
      ; sok_digest = ()
      ; zkapp_updates_applied
      }
      : t )
end

include Wire_types.Make (Make_sig) (Make_str)
