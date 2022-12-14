(** {1: A Git key-value store.}

    This module implements the ability to manipulate a Git repository as a
    Key-Value store. It allows you to create a local (in-memory) Git repository
    that can come from either:
    - a remote Git repository (with {!val:connect})
    - a state serialized by the {!val:to_octets} function

    The first case is interesting if you want to be synchronised with the
    remote repository. The second case can be interesting if we {b don't} want
    to create a connection at the beginning and desynchronisation between our
    local and remote repositories {b is not} a problem.

    In the second case, the synchronisation can be done later with {!val:pull}.

    {2: Pushing and synchronisation.}

    The user can modify the repository (add files, remove files, etc.). Each
    change produces a commit and after each change we try to transfer them to
    the remote Git repository. If you want to make multiple changes but contain
    them in a single commit and only transfer those changes once, you should
    use the {!val:Make.change_and_push} function.

    {2: Serialization of the Git repository.}

    Finally, the KV-store tries to keep the minimal set of commits required
    between you and the remote repository. Only {i un}pushed changes are kept
    by the KV-store. However, if these changes are not pushed, they will be
    stored into the final state produced by {!val:to_octets}. In other words,
    the more changes you make out of sync with the remote repository (without
    pushing them), the bigger the state serialization will be. *)

type t
(** The type of the Git store. *)

val connect : Mimic.ctx -> string -> t Lwt.t
(** [connect ctx remote] creates a new Git store which synchronises
    with [remote] {i via} protocols available into the given [ctx].

    @raise [Invalid_argument _] if we can not initialize the store, or if
    we can not fetch the given [remote]. *)

val to_octets : t -> string Lwt.t
(** [to_octets store] returns a serialized version of the given [store]. *)

val of_octets : Mimic.ctx -> remote:string -> string ->
  (t, [> `Msg of string]) result Lwt.t
(** [of_octets ctx ~remote contents] tries to re-create a {!type:t} from its
    serialized version [contents]. This function does not do I/O and the
    returned {!type:t} can be out of sync with the given [remote]. We advise
    to call {!val:pull} to be in-sync with [remote]. *)

type change = [ `Add of Mirage_kv.Key.t
              | `Remove of Mirage_kv.Key.t
              | `Change of Mirage_kv.Key.t ]

val pull : t -> (change list, [> `Msg of string ]) result Lwt.t
(** [pull store] tries to synchronise the remote Git repository with your local
    [store] Git repository. It returns a list of changes between the old state
    of your store and what you have remotely. *)

module Make (Pclock : Mirage_clock.PCLOCK) : sig
  include Mirage_kv.RW
    with type t = t
     and type write_error = [ `Msg of string
                            | `Hash_not_found of Digestif.SHA1.t
                            | `Reference_not_found of Git.Reference.t
                            | Mirage_kv.write_error ]
     and type error = [ `Msg of string | Mirage_kv.error ]

  val change_and_push : t -> (t -> 'a Lwt.t) -> ('a, [> `Msg of string ]) result Lwt.t
end
