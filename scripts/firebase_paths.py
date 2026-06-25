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

    # --- Storage ---
    @staticmethod
    def storage_logo(church_id: str) -> str:
        return f"{FirebasePaths.igreja(church_id)}/configuracoes/logo_igreja.png"

