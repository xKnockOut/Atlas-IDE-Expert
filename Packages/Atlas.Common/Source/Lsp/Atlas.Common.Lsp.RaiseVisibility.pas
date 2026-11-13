unit Atlas.Common.Lsp.RaiseVisibility;

// „Sichtbarkeit anheben“ und „Eigenschaft anlegen“ über das Protokoll (#2108):
//   - Code-Aktionen „Sichtbarkeit von X auf protected/public anheben“ auf der
//     Deklaration eines Mitglieds (refactoring.raiseVisibility).
//   - Befehl atlas.server.memberActions [uri, position, name]: die Aktionen
//     für ein Mitglied, das die Vervollständigung als nicht sichtbar meldet,
//     als Code-Aktionen mit WorkspaceEdit für die Datei der Deklaration; zuerst
//     „Eigenschaft anlegen“ (nur bei Feldern), dann „Sichtbarkeit anheben“. Die
//     Datei muss nicht im Editor geöffnet sein.
// Die Änderungen selbst liefert Atlas.Common.Editing.RaiseVisibility.

interface

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TLspRaiseVisibility = class
  public const
    cCommand = 'atlas.server.memberActions';
  public
    /// <summary>Code-Aktionen „Sichtbarkeit anheben“ für das Mitglied an ARange.StartPos als JSON; der Aufrufer
    /// übernimmt die Objekte.</summary>
    class function Actions(const AUri, AText: string; ATree: TSyntaxTree; const ARange: TTextRange):
      TArray<TJSONObject>; static;
    /// <summary>Alle Aktionen für das Mitglied AName, dessen Deklaration an APosition in AText steht, als
    /// JSON-Array von Code-Aktionen; leer, wenn es keine gibt. Parst AText selbst. Der Aufrufer übernimmt das
    /// Array.</summary>
    class function Execute(const AUri, AText: string; const APosition: TTextPosition; const AName: string):
      TJSONArray; static;
  end;

implementation

uses
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.RaiseVisibility,
  Atlas.Common.Lsp.CodeActions;

class function TLspRaiseVisibility.Actions(const AUri, AText: string; ATree: TSyntaxTree;
  const ARange: TTextRange): TArray<TJSONObject>;
var
  mAction: TCodeAction;
begin
  Result := nil;
  for mAction in TRaiseVisibility.Actions(AText, ATree, ARange.StartPos, '', False) do
  begin
    Result := Result + [TLspCodeActions.ActionToJson(AUri, mAction)];
  end;
end;

class function TLspRaiseVisibility.Execute(const AUri, AText: string; const APosition: TTextPosition;
  const AName: string): TJSONArray;
var
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  Result := TJSONArray.Create;
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    for mAction in TRaiseVisibility.Actions(AText, mTree, APosition, AName, True) do
    begin
      Result.AddElement(TLspCodeActions.ActionToJson(AUri, mAction));
    end;
  finally
    mTree.Free;
  end;
end;

end.
