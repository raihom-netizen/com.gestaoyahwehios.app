  Widget _buildMembersListFutureColumn(EdgeInsets padding, {required bool addBlocked}) {
                    Expanded(
                      child:
                          FutureBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
                        future: _membersDataFuture,
                        builder: (context, snap) {
                          if (snap.connectionState != ConnectionState.done)
                            return const SkeletonLoader(itemCount: 8);
                          if (snap.hasError) {
                            return Padding(
                              padding:
                                  const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                              child: ChurchPanelErrorBody(
                                title: 'Não foi possível carregar os membros',
                                error: snap.error,
                                onRetry: _refreshMembers,
                              ),
                            );
                          }
                          final list = snap.data!;
                          if (list.length < 7) {
                            return Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.warning_amber_rounded,
                                        size: 48, color: Colors.amber.shade700),
                                    const SizedBox(
                                        height: ThemeCleanPremium.spaceMd),
                                    Text(
                                      'Resposta incompleta ao carregar membros (${list.length}/7).',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color:
                                              ThemeCleanPremium.onSurfaceVariant),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                        onPressed: _refreshMembers,
                                        icon: const Icon(Icons.refresh_rounded),
                                        label: const Text('Recarregar')),
                                  ],
                                ),
                              ),
                            );
                          }
                          final pendCount = list[6].docs.length;
                          final combined = <String, _MemberDoc>{};
                          void putOrMerge(
                              QueryDocumentSnapshot<Map<String, dynamic>> d,
                              _MemberDoc Function(
                                      QueryDocumentSnapshot<Map<String, dynamic>>)
                                  map) {
                            final doc = map(d);
                            final cur = combined[doc.id];
                            if (cur == null) {
                              combined[doc.id] = doc;
                            } else {
                              combined[doc.id] = _MemberDoc(doc.id,
                                  _mergeMemberPhotoFields(cur.data, doc.data));
                            }
                          }

                          // list[0]..[3] são mesmas fontes mescladas (membros igreja); um loop evita merge quadruplicado.
                          for (final d in list[0].docs)
                            putOrMerge(d, _MemberDoc.fromQueryDoc);
                          for (final d in list[4].docs)
                            putOrMerge(d, _MemberDoc.fromUserDoc);
                          for (final d in list[5].docs)
                            putOrMerge(d, _MemberDoc.fromUserDoc);
                          final allDocs = combined.values
                              .map(_memberWithOptimisticOverlay)
                              .where((m) =>
                                  !_optimisticRemovedMemberIds.contains(m.id))
                              .toList();
                          final docs = _aplicarFiltros(allDocs);
                          final bootDocId =
                              widget.initialOpenMemberDocId?.trim() ?? '';
                          if (bootDocId.isNotEmpty &&
                              !_didBootstrapOpenMemberSheet) {
                            _didBootstrapOpenMemberSheet = true;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              _MemberDoc? hit;
                              for (final d in allDocs) {
                                if (d.id == bootDocId) {
                                  hit = d;
                                  break;
                                }
                              }
                              if (hit != null) {
                                _showMemberDetails(context, hit);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Membro não encontrado na lista (id: $bootDocId). Atualize ou verifique o cadastro.',
                                    ),
                                  ),
                                );
                              }
                            });
                          }
                          final pendentesNaLista = docs
                              .where((d) => _memberDocIsPending(d.data))
                              .toList();
                          Widget listContent;
                          if (docs.isEmpty) {
                            final filteredOut = allDocs.isNotEmpty;
                            if (_q.isNotEmpty) {
                              listContent = Center(
                                  child: Text(
                                      'Nenhum membro encontrado para "$_q".',
                                      style: TextStyle(
                                          color:
                                              ThemeCleanPremium.onSurfaceVariant)));
                            } else if (filteredOut) {
                              listContent = Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(
                                      ThemeCleanPremium.spaceLg),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.filter_alt_off_rounded,
                                          size: 64, color: Colors.grey.shade400),
                                      const SizedBox(
                                          height: ThemeCleanPremium.spaceMd),
                                      Text(
                                        'Nenhum membro corresponde aos filtros ativos.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: ThemeCleanPremium.onSurface),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Há ${allDocs.length} na lista bruta. Ajuste a aba Todos/Ativos/Inativos ou os filtros avançados.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 13,
                                            height: 1.35,
                                            color: ThemeCleanPremium
                                                .onSurfaceVariant),
                                      ),
                                      const SizedBox(height: 20),
                                      FilledButton.icon(
                                        onPressed: () => setState(() {
                                          _filtroStatus = 'todos';
                                          _filtroGenero = 'todos';
                                          _filtroFaixaEtaria = 'todas';
                                          _filtroDiaCadastro = 'todos';
                                          _filtroDepartamento = 'todos';
                                          _filtroAniversarioMes = null;
                                        }),
                                        icon: const Icon(Icons.restart_alt_rounded,
                                            size: 20),
                                        label: const Text('Limpar filtros'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            } else if (!_canManage &&
                                AppPermissions.isRestrictedMember(widget.role) &&
                                allDocs.isEmpty) {
                              listContent = Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(
                                      ThemeCleanPremium.spaceLg),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.badge_outlined,
                                          size: 64, color: Colors.grey.shade400),
                                      const SizedBox(
                                          height: ThemeCleanPremium.spaceMd),
                                      Text(
                                        'Cadastro não encontrado para este login.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: ThemeCleanPremium.onSurface),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'O CPF do login deve coincidir com o cadastro ou a ficha precisa estar vinculada ao seu usuário. Em caso de dúvida, fale com o secretariado.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 13,
                                            height: 1.35,
                                            color: ThemeCleanPremium
                                                .onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            } else {
                              listContent = Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(
                                      ThemeCleanPremium.spaceLg),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.people_outline_rounded,
                                          size: 64, color: Colors.grey.shade400),
                                      const SizedBox(
                                          height: ThemeCleanPremium.spaceMd),
                                      Text('Nenhum membro cadastrado.',
                                          style: TextStyle(
                                              fontSize: 16,
                                              color: ThemeCleanPremium
                                                  .onSurfaceVariant)),
                                      if (_canManage) ...[
                                        const SizedBox(height: 16),
                                        FilledButton.icon(
                                          onPressed: addBlocked
                                              ? null
                                              : () => _onAddMember(context),
                                          icon: const Icon(Icons.person_add_rounded,
                                              size: 20),
                                          label: Text(addBlocked
                                              ? 'Limite do plano'
                                              : 'Cadastrar novo membro'),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }
                          } else {
                            listContent = _buildMembersList(docs);
                          }
                          final allPendIds =
                              pendentesNaLista.map((e) => e.id).toSet();
                          final allPendingSelected = allPendIds.isNotEmpty &&
                              allPendIds.every(_selectedPendingIds.contains);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_filtroStatus == 'pendentes' &&
                                  _canApprovePending &&
                                  pendentesNaLista.isNotEmpty)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(padding.horizontal,
                                      0, padding.horizontal, 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                                      border: Border.all(
                                          color: const Color(0xFFF1F5F9)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFFFBEB),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                  Icons.pending_actions_rounded,
                                                  color: Colors.amber.shade800,
                                                  size: 22),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${pendentesNaLista.length} pendente(s) na lista',
                                                    style: const TextStyle(
                                                        fontWeight: FontWeight.w800,
                                                        fontSize: 15,
                                                        letterSpacing: -0.2),
                                                  ),
                                                  Text(
                                                    'Aprove um por um no menu ⋮, selecione vários ou todos de uma vez.',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey.shade600,
                                                        height: 1.3),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          children: [
                                            OutlinedButton.icon(
                                              onPressed: () => setState(() {
                                                if (allPendingSelected) {
                                                  _selectedPendingIds.removeWhere(
                                                      allPendIds.contains);
                                                } else {
                                                  _selectedPendingIds = {
                                                    ..._selectedPendingIds,
                                                    ...allPendIds
                                                  };
                                                }
                                              }),
                                              icon: Icon(
                                                  allPendingSelected
                                                      ? Icons.deselect_rounded
                                                      : Icons.select_all_rounded,
                                                  size: 18),
                                              label: Text(allPendingSelected
                                                  ? 'Limpar seleção'
                                                  : 'Selecionar todos'),
                                              style: OutlinedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 14, vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(12)),
                                              ),
                                            ),
                                            FilledButton.icon(
                                              onPressed: _selectedPendingIds.isEmpty
                                                  ? null
                                                  : () => _aprovarMembrosPorIds(
                                                      Set<String>.from(
                                                          _selectedPendingIds
                                                              .intersection(
                                                                  allPendIds))),
                                              icon: const Icon(
                                                  Icons.check_circle_rounded,
                                                  size: 18),
                                              label: Text(
                                                  'Aprovar selecionados (${_selectedPendingIds.intersection(allPendIds).length})'),
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFF059669),
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 16, vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(12)),
                                              ),
                                            ),
                                            FilledButton.tonalIcon(
                                              onPressed: () =>
                                                  _confirmAprovarTodosFiltrados(
                                                      pendentesNaLista),
                                              icon: const Icon(
                                                  Icons.done_all_rounded,
                                                  size: 18),
                                              label: const Text(
                                                  'Aprovar todos filtrados'),
                                              style: FilledButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 16, vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(12)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (_canApprovePending && pendCount > 0)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                      padding.horizontal, 0, padding.horizontal, 8),
                                  child: Material(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(
                                        ThemeCleanPremium.radiusSm),
                                    child: InkWell(
                                      onTap: () async {
                                        await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    AprovarMembrosPendentesPage(
                                                        tenantId:
                                                            _effectiveTenantId,
                                                        gestorRole: widget.role)));
                                        if (mounted) _refreshMembers();
                                      },
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusSm),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 12),
                                        child: Row(children: [
                                          Icon(Icons.person_add_rounded,
                                              color: Colors.amber.shade800,
                                              size: 22),
                                          const SizedBox(width: 10),
                                          Expanded(
                                              child: Text(
                                                  '$pendCount cadastro(s) pendente(s) de aprovação',
                                                  style: TextStyle(
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 13,
                                                      color:
                                                          Colors.amber.shade900))),
                                          Icon(Icons.arrow_forward_rounded,
                                              color: Colors.amber.shade800,
                                              size: 20),
                                        ]),
                                      ),
                                    ),
                                  ),
                                ),
                              Expanded(
                                  child: _wrapMembersListScroll(
                                onRefresh: () async =>
                                    _refreshMembers(forceServer: true),
                                docsEmpty: docs.isEmpty,
                                listContent: listContent,
                              )),
                            ],
                          );
                        },
                      ),
  }

