"""Paths canônicos Firebase (Firestore + Storage) para uso em scripts Python.

Regra: nunca hardcode de tenant; sempre passar church_id dinamicamente.
"""


class FirebasePaths:
    # --- Firestore geral ---
    @staticmethod
    def igreja(church_id: str) -> str:
        return f"igrejas/{church_id.strip()}"

    @staticmethod
    def departamentos(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/departamentos"

    @staticmethod
    def departamento_doc(church_id: str, dept_id: str) -> str:
        return f"{FirebasePaths.departamentos(church_id)}/{dept_id.strip()}"

    @staticmethod
    def membros(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/membros"

    @staticmethod
    def visitantes(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/visitantes"

    @staticmethod
    def cargos(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/cargos"

    @staticmethod
    def mural_avisos(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/mural_avisos"

    @staticmethod
    def eventos(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/eventos"

    @staticmethod
    def chat_messages(church_id: str, chat_id: str) -> str:
        return f"{FirebasePaths.chats(church_id)}/{chat_id.strip()}/messages"

    @staticmethod
    def chats(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/chats"

    @staticmethod
    def escalas(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/escalas"

    @staticmethod
    def certificados(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/certificados"

    @staticmethod
    def patrimonio(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/patrimonio"

    @staticmethod
    def pedidos_oracao(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/pedidosOracao"

    @staticmethod
    def transferencias(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/cartas_historico"

    @staticmethod
    def config_mercado_pago(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/config/mercado_pago"

    # --- Financeiro ---
    @staticmethod
    def finance(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/finance"

    @staticmethod
    def finance_doc(church_id: str, finance_id: str) -> str:
        return f"{FirebasePaths.finance(church_id)}/{finance_id.strip()}"

    @staticmethod
    def finance_logs(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/finance_logs"

    @staticmethod
    def finance_mp_notifications(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/finance_mp_notifications"

    # --- Fornecedores ---
    @staticmethod
    def fornecedores(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/fornecedores"

    @staticmethod
    def fornecedor_doc(church_id: str, fornecedor_id: str) -> str:
        return f"{FirebasePaths.fornecedores(church_id)}/{fornecedor_id.strip()}"

    @staticmethod
    def fornecedor_compromissos(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/fornecedor_compromissos"

    @staticmethod
    def fornecedor_compromisso_doc(church_id: str, compromisso_id: str) -> str:
        return (
            f"{FirebasePaths.fornecedor_compromissos(church_id)}/{compromisso_id.strip()}"
        )

    # Alias para compatibilidade com nomenclatura legada mencionada em prompts.
    @staticmethod
    def proveedores_fornecedores(church_id: str) -> str:
        return FirebasePaths.fornecedores(church_id)

    # --- Storage (canónico igrejas/{churchId}/…) ---
    @staticmethod
    def storage_root(church_id: str) -> str:
        return FirebasePaths.igreja(church_id)

    @staticmethod
    def storage_logo(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/configuracoes/logo_igreja.png"

    @staticmethod
    def storage_member_profile_photo(church_id: str, member_folder_id: str) -> str:
        safe = member_folder_id.strip().replace("/", "_") or "doc"
        return f"{FirebasePaths.igreja(church_id)}/membros/{safe}/foto_perfil.jpg"

    @staticmethod
    def storage_aviso_photo(church_id: str, post_id: str, slot_index: int) -> str:
        root = f"{FirebasePaths.igreja(church_id)}/avisos/{post_id.strip()}"
        if slot_index <= 0:
            return f"{root}/capa_aviso.jpg"
        n = str(slot_index).zfill(2)
        return f"{root}/galeria_{n}.jpg"

    @staticmethod
    def storage_evento_photo(church_id: str, post_id: str, slot_index: int) -> str:
        pid = post_id.strip()
        n = max(1, min(10, slot_index + 1))
        return f"{FirebasePaths.igreja(church_id)}/eventos/{pid}/fotos/foto_{n}.jpg"

    @staticmethod
    def storage_evento_video(church_id: str, post_id: str, video_slot: int = 0) -> str:
        pid = post_id.strip()
        s = max(0, min(1, video_slot))
        return f"{FirebasePaths.igreja(church_id)}/eventos/videos/{pid}_v{s}.mp4"

    @staticmethod
    def storage_evento_video_thumb(church_id: str, post_id: str, video_slot: int = 0) -> str:
        pid = post_id.strip()
        s = max(0, min(1, video_slot))
        return f"{FirebasePaths.igreja(church_id)}/eventos/thumbs/{pid}_v{s}.webp"

    @staticmethod
    def storage_patrimonio_photo(church_id: str, item_id: str, slot: int) -> str:
        safe = item_id.strip().replace("/", "_") or "doc"
        n = max(1, min(4, slot + 1))
        return f"{FirebasePaths.igreja(church_id)}/patrimonio/{safe}/foto_{n}.jpg"

    @staticmethod
    def storage_finance_comprovante(
        church_id: str,
        lancamento_id: str,
        year: int,
        month: int,
        ext: str = "jpg",
    ) -> str:
        ym = f"{year}_{str(month).zfill(2)}"
        lid = lancamento_id.strip() or "doc"
        safe_ext = ext.lstrip(".") or "jpg"
        return f"{FirebasePaths.igreja(church_id)}/financeiro/{ym}/{lid}.{safe_ext}"

    @staticmethod
    def storage_chat_media_prefix(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/chat_media/"

    @staticmethod
    def storage_cartao_membro_logo(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/cartao_membro/logo.jpg"

    @staticmethod
    def storage_certificados_prefix(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/certificados/"

    @staticmethod
    def storage_marketing_capa(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/marketing_destaque/capa.jpg"

    @staticmethod
    def storage_fornecedor_comprovante(
        church_id: str,
        fornecedor_id: str,
        compromisso_id: str,
        ext: str = "jpg",
    ) -> str:
        fid = fornecedor_id.strip() or "doc"
        cid = compromisso_id.strip() or "doc"
        safe_ext = ext.lstrip(".") or "jpg"
        return (
            f"{FirebasePaths.igreja(church_id)}/fornecedores/{fid}/"
            f"compromissos/{cid}_comprovante.{safe_ext}"
        )

