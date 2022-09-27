let () = Printexc.record_backtrace true

open Rresult
open Lwt.Infix

let get ~quiet store key =
  Git_kv.get store key >>= function
  | Ok contents when not quiet ->
    Fmt.pr "@[<hov>%a@]\n%!" (Hxd_string.pp Hxd.default) contents ;
    Lwt.return (Ok 0)
  | Ok _ -> Lwt.return (Ok 0)
  | Error err ->
    if not quiet then Fmt.epr "%a.\n%!" Git_kv.pp_error err ;
    Lwt.return (Ok 1)

let list ~quiet store key =
  Git_kv.list store key >>= function
  | Ok lst when not quiet ->
    List.iter (fun (name, k) -> match k with
    | `Dictionary -> Fmt.pr "d %s\n%!" name
    | `Value -> Fmt.pr "- %s\n%!" name) lst ;
    Lwt.return (Ok 0)
  | Ok _ -> Lwt.return (Ok 0)
  | Error err ->
    if not quiet then Fmt.epr "%a.\n%!" Git_kv.pp_error err ;
    Lwt.return (Ok 1)

let pull ~quiet store =
  Git_kv.pull store >>= function
  | Error (`Msg err) -> if not quiet then Fmt.epr "%s.\n%!" err ; Lwt.return (Ok 1)
  | Ok diff when not quiet ->
    List.iter (function
    | `Add key -> Fmt.pr "+ %a\n%!" Mirage_kv.Key.pp key
    | `Remove key -> Fmt.pr "- %a\n%!" Mirage_kv.Key.pp key
    | `Change key -> Fmt.pr "* %a\n%!" Mirage_kv.Key.pp key) diff ;
    Lwt.return (Ok 0)
  | Ok _ -> Lwt.return (Ok 0)

let save store filename =
  let oc = open_out filename in
  Git_kv.to_octets store >>= fun contents ->
  output_string oc contents ;
  close_out oc ;
  Lwt.return (Ok 0)

let trim lst =
  List.fold_left (fun acc -> function
    | "" -> acc
    | str -> str :: acc) [] lst |> List.rev

let with_key ~f key =
  match Mirage_kv.Key.v key with
  | key -> f key
  | exception _ ->
    Fmt.epr "Invalid key: %S.\n%!" key ;
    Lwt.return (Ok 1)

let repl store ic =
  let rec go () = Fmt.pr "# %!" ; match String.split_on_char ' ' (input_line ic) |> trim with
    | [ "get"; key; ] ->
      with_key ~f:(get ~quiet:false store) key >|= ignore >>= go
    | [ "list"; key; ] ->
      with_key ~f:(list ~quiet:false store) key >|= ignore >>= go
    | [ "pull"; ] ->
      Fmt.pr "\n%!" ; pull ~quiet:false store >|= ignore >>= go
    | [ "quit"; ] -> Lwt.return ()
    | [ "save"; filename ] ->
      save store filename >|= ignore >>= fun _ ->
      Fmt.pr "\n%!" ; go ()
    | _ -> Fmt.epr "Invalid command.\n%!" ; go ()
    | exception End_of_file -> Lwt.return () in
  go ()

let run remote = function
  | None ->
    Lwt_main.run @@
    (Git_unix.ctx (Happy_eyeballs_lwt.create ()) >>= fun ctx ->
     Git_kv.connect ctx remote >>= fun t ->
     repl t stdin)
  | Some filename ->
    let contents =
      let ic = open_in filename in
      let ln = in_channel_length ic in
      let bs = Bytes.create ln in
      really_input ic bs 0 ln ;
      Bytes.unsafe_to_string bs in
    Lwt_main.run
    ( Git_unix.ctx (Happy_eyeballs_lwt.create ()) >>= fun ctx ->
      Git_kv.of_octets ctx ~remote contents >>= function
    | Ok t -> repl t stdin
    | Error (`Msg err) -> Fmt.failwith "%s." err )

let () = match Sys.argv with
  | [| _; remote; |] -> run remote None
  | [| _; remote; filename; |] when Sys.file_exists filename ->
    run remote (Some filename)
  | _ -> Fmt.epr "%s <remote> [<filename>]\n%!" Sys.argv.(0)