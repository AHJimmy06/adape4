-- Optional TWO-session probe; ONLY use UUID fixtures in an isolated test database.
-- Required psql variables: usuario_id, vuelo_id, asiento, clave_operacion.
-- Run this file concurrently in two terminals using different users/keys but
-- the same flight/seat. The winner holds its transaction for five seconds then
-- commits; the loser waits and raises CONFLICTO. Do not target production rows.
-- Automated equivalent (creates its own isolated DB):
-- pytest backend/tests/test_sistema_integracion.py::test_two_real_connections_same_seat_one_winner
\if :{?usuario_id}
\else
\echo 'Missing explicit isolated fixture usuario_id; refusing.'
\quit
\endif
\if :{?vuelo_id}
\else
\echo 'Missing explicit isolated fixture vuelo_id; refusing.'
\quit
\endif
\if :{?asiento}
\else
\echo 'Missing explicit isolated fixture asiento; refusing.'
\quit
\endif
\if :{?clave_operacion}
\else
\echo 'Missing explicit isolated fixture clave_operacion; refusing.'
\quit
\endif
begin;
select public.sistema_operar('crear_pedido',:'usuario_id'::uuid,
 jsonb_build_object('vuelo_id',:'vuelo_id','asientos',jsonb_build_array(:'asiento'),'clave_operacion',:'clave_operacion'));
select pg_sleep(5);
commit;
