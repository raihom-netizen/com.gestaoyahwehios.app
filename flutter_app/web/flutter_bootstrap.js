{{flutter_js}}
{{flutter_build_config}}

// Service worker desativado: evita cache da versão antiga após deploy (usuário sempre carrega a versão nova).
_flutter.loader.load({
  config: {
    renderer: "canvaskit",
  },
});
