/**
 * Identidade Super Premium para FCM e e-mails — logo Gestão YAHWEH + cor por módulo.
 * Logo servido pelo Hosting (`web/brand/gestao_yahweh_mark.png` em deploy web).
 */
import * as admin from "firebase-admin";
import { defineString } from "firebase-functions/params";

const PUBLIC_WEB_BASE = defineString("PUBLIC_WEB_BASE_URL", {
  default: "https://gestaoyahweh.com.br",
});

/** PNG marca (512px+); mesmo URL nos e-mails e imagem rica do push. */
export function gestaoBrandLogoUrl(): string {
  const base = PUBLIC_WEB_BASE.value().trim().replace(/\/$/, "");
  return `${base}/brand/gestao_yahweh_mark.png`;
}

/** Alinhado ao menu do painel ([kChurchShellNavEntries] Flutter). */
export type GyModuleKind =
  | "aviso"
  | "evento"
  | "escala"
  | "fornecedor_agenda"
  | "pastoral"
  | "devocional"
  | "aniversario"
  | "financeiro"
  | "membro"
  | "generico"
  | "chat";

export function moduleAccentHex(kind: GyModuleKind): string {
  switch (kind) {
    case "aviso":
      return "#0EA5E9";
    case "evento":
      return "#F97316";
    case "escala":
      return "#14B8A6";
    case "fornecedor_agenda":
      return "#475569";
    case "pastoral":
      return "#EAB308";
    case "devocional":
      return "#6366F1";
    case "aniversario":
      return "#E11D48";
    case "financeiro":
      return "#37474F";
    case "membro":
      return "#2563EB";
    case "generico":
      return "#3B82F6";
    case "chat":
      return "#8B5CF6";
    default:
      return "#3B82F6";
  }
}

function mergeData(
  data: Record<string, string>,
  module: GyModuleKind
): Record<string, string> {
  return {
    ...data,
    gy_module: module,
    gy_brand: "gestao_yahweh",
  };
}

/** Push por tópico — imagem rica + barra de cor (Android) + APNS image. */
export function buildGyTopicMessage(params: {
  topic: string;
  title: string;
  body: string;
  data: Record<string, string>;
  module: GyModuleKind;
}): admin.messaging.Message {
  const img = gestaoBrandLogoUrl();
  const color = moduleAccentHex(params.module);
  const data = mergeData(params.data, params.module);
  return {
    topic: params.topic,
    notification: {
      title: params.title,
      body: params.body,
      imageUrl: img,
    },
    data,
    android: {
      priority: "high",
      notification: {
        imageUrl: img,
        color,
      },
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          mutableContent: true,
        },
      },
      fcmOptions: {
        imageUrl: img,
      },
    },
  };
}

/** Push direto para um token FCM. */
export function buildGyTokenMessage(params: {
  token: string;
  title: string;
  body: string;
  data: Record<string, string>;
  module: GyModuleKind;
  /**
   * Chat: som/vibração/silêncio em **segundo plano** (Android `channelId` + APNS).
   * Os IDs de canal devem existir na app — ver `ChurchChatAlertNotificationService` (Flutter).
   */
  chatDelivery?: {
    androidChannelId: string;
    /** `null` = omitir `aps.sound` (iOS: sem toque do sistema; ainda pode vibrar em hardware). */
    iosSound: string | null;
    /** ex.: `passive` para entrega mais discreta quando [iosSound] é null. */
    iosInterruptionLevel?: "active" | "passive";
  };
}): admin.messaging.Message {
  const img = gestaoBrandLogoUrl();
  const color = moduleAccentHex(params.module);
  const data = mergeData(params.data, params.module);
  const chat = params.chatDelivery;
  const aps: Record<string, unknown> = {
    mutableContent: true,
  };
  const apnsHeaders: Record<string, string> = {
    "apns-priority": "10",
  };
  if (chat) {
    if (chat.iosSound != null && chat.iosSound.length > 0) {
      aps.sound = chat.iosSound;
    }
    if (chat.iosInterruptionLevel) {
      apnsHeaders["apns-interruption-level"] = chat.iosInterruptionLevel;
    }
  } else {
    aps.sound = "default";
  }
  const androidNotif: admin.messaging.AndroidNotification = {
    imageUrl: img,
    color,
    ...(chat?.androidChannelId ? { channelId: chat.androidChannelId } : {}),
  };
  return {
    token: params.token,
    notification: {
      title: params.title,
      body: params.body,
      imageUrl: img,
    },
    data,
    android: {
      priority: "high",
      notification: androidNotif,
    },
    apns: {
      headers: apnsHeaders,
      payload: {
        aps,
      },
      fcmOptions: {
        imageUrl: img,
      },
    },
  };
}

/** Cabeçalho HTML dos e-mails SendGrid — gradiente por módulo + logo. */
export type GyEmailModule =
  | "aviso"
  | "escala"
  | "evento"
  | "aniversario"
  | "generico";

export function emailHeaderGradient(module: GyEmailModule): string {
  switch (module) {
    case "aviso":
      return "linear-gradient(135deg,#0EA5E9 0%,#0369A1 100%)";
    case "escala":
      return "linear-gradient(135deg,#14B8A6 0%,#0F766E 100%)";
    case "evento":
      return "linear-gradient(135deg,#F97316 0%,#C2410C 100%)";
    case "aniversario":
      return "linear-gradient(135deg,#FB7185 0%,#BE123C 100%)";
    case "generico":
    default:
      return "linear-gradient(135deg,#0A3D91 0%,#1E40AF 100%)";
  }
}

export function emailModuleBadgeLabel(module: GyEmailModule): string {
  switch (module) {
    case "aviso":
      return "Mural de avisos";
    case "escala":
      return "Escalas";
    case "evento":
      return "Eventos";
    case "aniversario":
      return "Aniversário";
    default:
      return "Gestão YAHWEH";
  }
}
