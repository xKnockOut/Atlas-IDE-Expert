unit Atlas.Common.Lsp.Completion.Guard;

// Freigabe absichern (#489): Nach "Liste := TStringList.Create;" schlägt die Vervollständigung try…finally vor.
// Aus Atlas.Common.Lsp.Completion herausgelöst.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Lsp.CompletionRequest;

type
  TCompletionGuard = class
  public
    /// <summary>Nach "Liste := TStringList.Create;" in der Zeile des Cursors „Mit try…finally absichern“ und,
    /// wenn danach noch Zeilen bis zum Routinenende folgen, dieselbe Absicherung bis dorthin; Freigabe nach
    /// Settings.FreeStyle. False, wenn die Anweisung nicht passt (TGuardFree.Check). ANewLine: Ausgelöst durch
    /// Enter am Zeilenende; die Anweisung steht dann in der Zeile davor, und die leere Zeile des Cursors wird
    /// ersetzt.</summary>
    class function GuardItems(ARequest: TCompletionRequest; ANewLine: Boolean;
      out AItems: TCompletionItems): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.GuardFree,
  Atlas.Common.Lsp.CompletionCollector,
  Atlas.Common.Lsp.Internals.CompletionSource,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Absicherung in beiden Sprachen (#1458).</summary>
  TGuardText = (NewLine, RoutineEnd);

const
  cTexts: array[TGuardText] of TAtlasText = (
    (De: 'Mit try…finally absichern'; En: 'Protect with try…finally'),
    (De: 'Bis Routinenende mit try…finally absichern'; En: 'Protect with try…finally up to the end of the routine'));
  cGuardKeys: array[TGuardText] of string = ('newLine', 'routineEnd');
  cGuardScopes: array[TGuardText] of TGuardScope = (TGuardScope.NewLine, TGuardScope.ToRoutineEnd);

/// <summary>Zeile der Anweisung: die des Cursors, nach Enter die davor (die des Cursors muss dann leer sein);
/// False ohne passende Zeile.</summary>
function StatementLine(ARequest: TCompletionRequest; ANewLine: Boolean; out ALine: Integer): Boolean;
var
  mLines: TArray<string>;
begin
  ALine := ARequest.Position.Line;
  Result := True;
  if ANewLine then
  begin
    mLines := ARequest.Lines;
    ALine := ARequest.Position.Line - 1;
    Result := (ALine >= 0) and (ARequest.Position.Line <= High(mLines)) and
      (Trim(mLines[ARequest.Position.Line]) = '');
  end;
end;

/// <summary>Art des erzeugten Typs: Record oder Interface schließen aus, TComponent-Nachfahren prüfen den Owner.
/// </summary>
function TypeKindFunc(ARequest: TCompletionRequest): TGuardTypeKindFunc;
var
  mUnit: TUnitIndex;
begin
  mUnit := ARequest.UnitIndex;
  Result :=
    function(const ATypeName: string): TGuardTypeKind
    var
      mSymbol: TResolvedSymbol;
    begin
      if not ARequest.Resolver.ResolveTypeFrom(mUnit, ATypeName, mSymbol) then
      begin
        Exit(TGuardTypeKind.Unknown);
      end;
      if mSymbol.SymbolKind <> TIndexSymbolKind.ClassType then
      begin
        Exit(TGuardTypeKind.Other);
      end;
      Result := TGuardTypeKind.Class_;
      if IndexText('TComponent', TypeChain(ARequest.Resolver, mUnit, ATypeName)) >= 0 then
      begin
        Result := TGuardTypeKind.Component;
      end;
    end;
end;

/// <summary>Eintrag für die Absicherung AKind.</summary>
function GuardItem(ARequest: TCompletionRequest; const AOffer: TGuardOffer; AKind: TGuardText): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Kind := cKindSnippet;
  Result.HasTextEdit := True;
  if ARequest.Settings.FreeStyle = TCompletionFreeStyle.FreeAndNil then
  begin
    Result.Detail := 'FreeAndNil(' + AOffer.Variable + ')';
  end
  else
  begin
    Result.Detail := AOffer.Variable + '.Free';
  end;
  Result.Name := cTexts[AKind].Text;
  Result.Guard := cGuardKeys[AKind];
  Result.TextEdit := TGuardFree.Edit(ARequest.Text, AOffer, cGuardScopes[AKind], ARequest.Settings.FreeStyle);
end;

class function TCompletionGuard.GuardItems(ARequest: TCompletionRequest; ANewLine: Boolean;
  out AItems: TCompletionItems): Boolean;
var
  mOffer: TGuardOffer;
  mLine: Integer;
begin
  AItems := Default(TCompletionItems);
  Result := StatementLine(ARequest, ANewLine, mLine) and
    TGuardFree.Check(ARequest.Tree, ARequest.Text, mLine, TypeKindFunc(ARequest), mOffer);
  if not Result then
  begin
    Exit;
  end;
  if ANewLine then
  begin
    mOffer.BlankLine := ARequest.Position.Line;
  end;
  AItems.Items := [GuardItem(ARequest, mOffer, TGuardText.NewLine)];
  if mOffer.CanEnclose then
  begin
    AItems.Items := AItems.Items + [GuardItem(ARequest, mOffer, TGuardText.RoutineEnd)];
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Completion.Guard', cTexts);

end.
