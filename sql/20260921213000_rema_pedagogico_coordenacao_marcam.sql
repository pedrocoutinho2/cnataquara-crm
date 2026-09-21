-- Pedagógico e coordenação também são responsáveis pela rematrícula: passam a marcar rema.
update crm_papel_permissoes set nivel='editar', atualizado_em=now() where modulo='rema' and papel in ('pedagogico','coordenacao');
