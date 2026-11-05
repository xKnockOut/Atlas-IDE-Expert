unit Atlas.Common.Editing.ClassActions;

// Klassen-Aktionen als Code-Aktionen (#42), mit denselben Erzeugern wie die
// Schnellbefehle und die Vervollständigung:
//   - "Getter, Setter und Feld für Name erzeugen" auf "property Name: Typ;"
//     ohne read/write: Feld FName, GetName und SetName (derselbe Setter wie
//     /prop) in einem private-Abschnitt vor der Property, Rümpfe hinter der
//     letzten Methode der Klasse
//   - "Methoden von IFoo implementieren" für jedes Interface im Kopf der
//     Klasse, dem noch Methoden fehlen (Erzeuger von /intf, #466)
//   - "Name überschreiben" für jede virtuelle Methode der Vorfahren, die die
//     Klasse noch nicht deklariert (Erzeuger von /override, Auswahl wie im
//     Erzeugen-Menü #719), höchstens MaxOverrides
//   - "Name anlegen" für ein fehlendes Feld F<Name>, Get<Name> oder Set<Name>
//     hinter read/write einer Property (Erzeuger der Vervollständigung #467,
//     Korrektur der Regel property-accessor-invalid #1001)
// Angeboten wird in der Deklaration einer Klasse (Kopfzeile bis vor "end").
// /intf und /override laufen über eine gedachte Befehlszeile hinter der
// Cursorzeile; ihre Änderungen werden auf den Text ohne diese Zeile
// zurückgerechnet.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.AccessorCreation;

type
  /// <summary>Umgebung der Klassen-Aktionen: Index für Vorfahren und Interfaces aus anderen Units, Formatstil.</summary>
  TClassActionContext = record
    Index: ISymbolIndex;
    Namespaces: TArray<string>;
    DelphiVersion: string;
    Uri: string;
    Style: TFormatStyle;
    /// <summary>Für die Einstellungen der Erzeuger (z. B. Abschnitt der Interface-Methoden); nil ohne.</summary>
    Host: ISlashHost;
    class function Default: TClassActionContext; static;
  end;

  TClassActions = class
  public const
    MaxOverrides = 20;
  public
    /// <summary>Alle Klassen-Aktionen für Zeile ALine; leer außerhalb einer Klassendeklaration.</summary>
    class function Actions(const AText: string; ATree: TSyntaxTree; ALine: Integer;
      const AContext: TClassActionContext): TArray<TCodeAction>; static;
    /// <summary>Getter, Setter und Feld zur Property in Zeile ALine; False, wenn dort keine Property ohne
    /// read/write steht oder alles schon da ist.</summary>
    class function PropertyAccessors(const AText: string; ALine: Integer; const AContext: TClassActionContext;
      out AAction: TCodeAction): Boolean; static;
    /// <summary>Fehlende Methoden von AInterface; False, wenn es kein Interface ist oder nichts fehlt.</summary>
    class function ImplementInterface(const AText: string; ALine: Integer; const AInterface: string;
      const AContext: TClassActionContext; out AAction: TCodeAction): Boolean; static;
    /// <summary>Virtuelle Methode AName eines Vorfahren überschreiben.</summary>
    class function OverrideMethod(const AText: string; ALine: Integer; const AName: string;
      const AContext: TClassActionContext; out AAction: TCodeAction): Boolean; static;
    /// <summary>Fehlendes Feld bzw. fehlende Zugriffsmethode APlan der Property in Zeile ALine anlegen (#1001);
    /// False, wenn es das Mitglied schon gibt oder ALine in keiner Klasse liegt.</summary>
    class function CreateAccessor(const AText: string; ALine: Integer; const APlan: TAccessorPlan;
      const AContext: TClassActionContext; out AAction: TCodeAction): Boolean; static;
    /// <summary>Überschreibbare Methoden der Vorfahren, die die Klasse um ALine noch nicht deklariert.</summary>
    class function OverrideCandidates(const AText: string; ALine: Integer;
      const AContext: TClassActionContext): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Editing.ClassCommands,
  Atlas.Common.Editing.ClassMembers,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TClassActionsText = (CreateGetterSetterAndField, Override, ImplementMethodsOf, Create);

const
  cTexts: array[TClassActionsText] of TAtlasText = (
    (De: 'Getter, Setter und Feld für %s erzeugen'; En: 'Create getter, setter and field for %s'),
    (De: '%s überschreiben'; En: 'Override %s'),
    (De: 'Methoden von %s implementieren'; En: 'Implement methods of %s'),
    (De: '%s anlegen'; En: 'Create %s'));

{$SCOPEDENUMS OFF}

{ TClassActionContext }

class function TClassActionContext.Default: TClassActionContext;
begin
  Result := System.Default(TClassActionContext);
  Result.Style := TFormatStyle.Default;
end;

/// <summary>Typdeklaration einer Klasse, deren Kopfzeile bis vor "end" ALine enthält; nil sonst.</summary>
function ClassDeclAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  if (ATree <> nil) and (ATree.Root <> nil) then
  begin
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode.StartPos.Line > ALine) or (ANode.EndPos.Line < ALine) then
        begin
          Exit(False);
        end;
        if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.FindChild(TSyntaxKind.ClassType) <> nil) and
          (ANode.EndPos.Line > ALine) then
        begin
          Found := ANode;
        end;
        Result := True;
      end);
  end;
  Result := Found;
end;

/// <summary>AText mit der Befehlszeile ACommand hinter Zeile ALine.</summary>
function PhantomText(const AText: string; ALine: Integer; const ACommand: string): string;
var
  Lines: TArray<string>;
  LB: string;
  Index: Integer;
begin
  Lines := TTextLines.SplitLines(AText);
  LB := TTextLines.LineBreakOf(AText);
  Result := '';
  for Index := 0 to High(Lines) do
  begin
    if Index > 0 then
    begin
      Result := Result + LB;
    end;
    Result := Result + Lines[Index];
    if Index = ALine then
    begin
      Result := Result + LB + TTextLines.IndentOf(Lines[Index]) + '  ' + ACommand;
    end;
  end;
end;

/// <summary>Position im Text mit Befehlszeile APhantom zurück auf den Text ohne sie.</summary>
function MapBack(const APosition: TTextPosition; APhantom: Integer): TTextPosition;
begin
  if APosition.Line < APhantom then
  begin
    Result := APosition;
  end
  else if APosition.Line = APhantom then
  begin
    Result := TTextPosition.Create(APhantom, 0);
  end
  else
  begin
    Result := TTextPosition.Create(APosition.Line - 1, APosition.Character);
  end;
end;

/// <summary>Führt ACommand als gedachte Zeile hinter ALine aus und rechnet die Änderungen zurück.</summary>
function RunPhantom(const AText: string; ALine: Integer; const ACommand: string; const AContext: TClassActionContext;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  Phantom, Reason: string;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
  Line: Integer;
begin
  AEdits := nil;
  Phantom := PhantomText(AText, ALine, ACommand);
  Line := ALine + 1;
  Result := TSlashCommandRegistry.Shared.Run(Phantom, Line, 0, TSlashEnvironment.Create(AContext.Namespaces, nil,
    AContext.Index, AContext.DelphiVersion, AContext.Uri, AContext.Host).WithStyle(AContext.Style), Edits, Reason);
  if not Result then
  begin
    Exit;
  end;
  for Edit in Edits do
  begin
    // Das Entfernen der Befehlszeile entfällt: Im echten Text gibt es sie nicht.
    if (Edit.NewText = '') and (Edit.Range.StartPos.Line = Line) and (Edit.Range.StartPos.Character = 0) and
      (Edit.Range.EndPos.Line = Line + 1) and (Edit.Range.EndPos.Character = 0) then
    begin
      Continue;
    end;
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(MapBack(Edit.Range.StartPos, Line),
      MapBack(Edit.Range.EndPos, Line)), Edit.NewText)];
  end;
  Result := AEdits <> nil;
end;

function SlashContext(const AText: string; ALine: Integer; const AContext: TClassActionContext): TSlashContext;
var
  Lines: TArray<string>;
begin
  Lines := TTextLines.SplitLines(AText);
  Result := System.Default(TSlashContext);
  Result.Text := AText;
  Result.Line := ALine;
  if (ALine >= 0) and (ALine <= High(Lines)) then
  begin
    Result.LineText := Lines[ALine];
  end;
  Result.Namespaces := AContext.Namespaces;
  Result.Index := AContext.Index;
  Result.DelphiVersion := AContext.DelphiVersion;
  Result.Style := AContext.Style;
  Result.Uri := AContext.Uri;
  Result.Host := AContext.Host;
end;

function HasMember(const AUnit: TUnitIndex; const AClassName, AName: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
  begin
    if SameText(Symbol.Container, AClassName) and SameText(Symbol.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

type
  /// <summary>Eigenschaft ohne read und write: "property Name: Typ; // Kommentar".</summary>
  TBareProperty = record
    Indent: string;
    Name: string;
    TypeName: string;
    /// <summary>Zeilenkommentar dahinter; '' ohne.</summary>
    Comment: string;
  end;

function ParseBareProperty(const ALine: string; out AProperty: TBareProperty): Boolean;
var
  mMatch: TMatch;
begin
  AProperty := Default(TBareProperty);
  mMatch := TRegEx.Match(ALine, '^(\s*)property\s+(\w+)\s*:\s*([^;]+?)\s*;\s*(//.*|)$', [roIgnoreCase]);
  Result := mMatch.Success and not TRegEx.IsMatch(mMatch.Groups[3].Value,
    '\b(read|write|index|default|stored|nodefault|implements)\b', [roIgnoreCase]);
  if Result then
  begin
    AProperty.Indent := mMatch.Groups[1].Value;
    AProperty.Name := mMatch.Groups[2].Value;
    AProperty.TypeName := mMatch.Groups[3].Value;
    AProperty.Comment := mMatch.Groups[4].Value;
  end;
end;

/// <summary>Deklarationen und Rümpfe der Mitglieder F&lt;Name&gt;, Get&lt;Name&gt; und Set&lt;Name&gt;, die der Klasse
/// AClass noch fehlen.</summary>
procedure MissingAccessors(ASource: TCommandSource; const AIndex: ISymbolIndex; const AClass: TIndexSymbol;
  const AProperty: TBareProperty; out ADeclarations, ABodies: string);
var
  mLB, mIndent, mField, mGetter, mSetter: string;
begin
  mLB := ASource.LineBreak;
  mIndent := ASource.Indent(AClass.Range.EndPos.Line) + '  ';
  mField := 'F' + AProperty.Name;
  mGetter := 'Get' + AProperty.Name;
  mSetter := 'Set' + AProperty.Name;
  ADeclarations := '';
  ABodies := '';
  if not HasMember(ASource.UnitIndex, AClass.Name, mField) then
  begin
    ADeclarations := ADeclarations + mIndent + Format('%s: %s;', [mField, AProperty.TypeName]) + mLB;
  end;
  if not HasMember(ASource.UnitIndex, AClass.Name, mGetter) then
  begin
    ADeclarations := ADeclarations + mIndent + Format('function %s: %s;', [mGetter, AProperty.TypeName]) + mLB;
    ABodies := Format('function %s.%s: %s;', [AClass.Name, mGetter, AProperty.TypeName]) + mLB + 'begin' + mLB +
      '  Result := ' + mField + ';' + mLB + 'end;';
  end;
  if not HasMember(ASource.UnitIndex, AClass.Name, mSetter) then
  begin
    ADeclarations := ADeclarations + mIndent + Format('procedure %s(const Value: %s);', [mSetter,
      AProperty.TypeName]) + mLB;
    if ABodies <> '' then
    begin
      ABodies := ABodies + mLB + mLB;
    end;
    // Derselbe Setter wie bei /prop: nur bei Änderung, mit Benachrichtigung.
    ABodies := ABodies + Format('procedure %s.%s(const Value: %s);', [AClass.Name, mSetter, AProperty.TypeName]) +
      mLB + TSetterGenerator.Body(mField, 'Value', TSetterGenerator.NotifyCall(ASource, AIndex, AClass), mLB);
  end;
end;

/// <summary>Ersatz der Eigenschaftszeile ALine: Feld und Zugriffsmethoden davor, denn Delphi verlangt sie vor ihrer
/// Verwendung, und Felder stehen in einem Abschnitt vor den Methoden. Danach geht der Abschnitt der Eigenschaft
/// weiter.</summary>
function PropertyReplacement(ASource: TCommandSource; const AClass: TIndexSymbol; ALine: Integer;
  const AProperty: TBareProperty; const ADeclarations: string): string;
var
  mLB, mIndent, mSection, mComment: string;
begin
  mLB := ASource.LineBreak;
  mIndent := ASource.Indent(AClass.Range.EndPos.Line);
  mSection := TInterfaceStubs.LastSection(ASource.Tree.Tokens, AClass.Range.StartPos.Line, ALine);
  if mSection = '' then
  begin
    mSection := 'public';
  end;
  mComment := AProperty.Comment;
  if mComment <> '' then
  begin
    mComment := ' ' + mComment;
  end;
  Result := mIndent + 'private' + mLB + ADeclarations + mIndent + mSection + mLB + AProperty.Indent +
    Format('property %s: %s read Get%s write Set%s;', [AProperty.Name, AProperty.TypeName, AProperty.Name,
    AProperty.Name]) + mComment;
end;

{ TClassActions }

class function TClassActions.PropertyAccessors(const AText: string; ALine: Integer;
  const AContext: TClassActionContext; out AAction: TCodeAction): Boolean;
var
  mLines: TArray<string>;
  mProperty: TBareProperty;
  mSource: TCommandSource;
  mClass: TIndexSymbol;
  mDeclarations, mBodies: string;
  mEdits: TArray<TTextEdit>;
begin
  AAction := Default(TCodeAction);
  Result := False;
  mLines := TTextLines.SplitLines(AText);
  if (ALine < 0) or (ALine > High(mLines)) or not ParseBareProperty(mLines[ALine], mProperty) then
  begin
    Exit;
  end;
  // Die Property-Zeile gilt als Befehlszeile: Der Baum sieht sie nicht, sie wird ohnehin ersetzt.
  mSource := TCommandSource.Create(SlashContext(AText, ALine, AContext));
  try
    if not mSource.ClassAt(mClass) or (mClass.Range.StartPos.Line >= ALine) or
      (mClass.Range.EndPos.Line <= ALine) then
    begin
      Exit;
    end;
    MissingAccessors(mSource, AContext.Index, mClass, mProperty, mDeclarations, mBodies);
    if mDeclarations = '' then
    begin
      Exit;
    end;
    mEdits := [TTextEdit.Create(TTextRange.Create(ALine, 0, ALine, Length(mLines[ALine])),
      PropertyReplacement(mSource, mClass, ALine, mProperty, mDeclarations))];
    if mBodies <> '' then
    begin
      mEdits := mEdits + [mSource.AddBody(mClass.Name, mBodies)];
    end;
  finally
    mSource.Free;
  end;
  AAction.Title := cTexts[TClassActionsText.CreateGetterSetterAndField].Fmt([mProperty.Name]);
  AAction.Kind := RewriteKind;
  AAction.Edits := TSlashCommandRegistry.Reindent(AText, mEdits, AContext.Style);
  Result := True;
end;

class function TClassActions.ImplementInterface(const AText: string; ALine: Integer; const AInterface: string;
  const AContext: TClassActionContext; out AAction: TCodeAction): Boolean;
begin
  AAction := Default(TCodeAction);
  Result := RunPhantom(AText, ALine, '/intf ' + AInterface, AContext, AAction.Edits);
  if Result then
  begin
    AAction.Title := cTexts[TClassActionsText.ImplementMethodsOf].Fmt([AInterface]);
    AAction.Kind := RewriteKind;
  end;
end;

class function TClassActions.OverrideMethod(const AText: string; ALine: Integer; const AName: string;
  const AContext: TClassActionContext; out AAction: TCodeAction): Boolean;
begin
  AAction := Default(TCodeAction);
  Result := RunPhantom(AText, ALine, '/override ' + AName, AContext, AAction.Edits);
  if Result then
  begin
    AAction.Title := cTexts[TClassActionsText.Override].Fmt([AName]);
    AAction.Kind := RewriteKind;
  end;
end;

class function TClassActions.CreateAccessor(const AText: string; ALine: Integer; const APlan: TAccessorPlan;
  const AContext: TClassActionContext; out AAction: TCodeAction): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Edits: TArray<TTextEdit>;
  WithField: Boolean;
begin
  AAction := Default(TCodeAction);
  // Die Property-Zeile gilt als Befehlszeile wie in der Vervollständigung; sie bleibt unverändert.
  Source := TCommandSource.Create(SlashContext(AText, ALine, AContext));
  try
    Result := Source.ClassAt(ClassSymbol) and TAccessorCreation.Edits(Source, AContext.Index, ClassSymbol, APlan,
      Edits, WithField);
  finally
    Source.Free;
  end;
  if not Result then
  begin
    Exit;
  end;
  AAction.Title := cTexts[TClassActionsText.Create].Fmt([APlan.Name]);
  AAction.Kind := RewriteKind;
  AAction.Edits := TSlashCommandRegistry.Reindent(AText, Edits, AContext.Style);
end;

class function TClassActions.OverrideCandidates(const AText: string; ALine: Integer;
  const AContext: TClassActionContext): TArray<string>;
var
  Phantom: string;
begin
  Phantom := PhantomText(AText, ALine, '/override');
  Result := Atlas.Common.Editing.ClassCommands.OverrideCandidates(SlashContext(Phantom, ALine + 1, AContext));
end;

class function TClassActions.Actions(const AText: string; ATree: TSyntaxTree; ALine: Integer;
  const AContext: TClassActionContext): TArray<TCodeAction>;
var
  Decl: TSyntaxNode;
  Action: TCodeAction;
  Name: string;
  Count: Integer;
begin
  Result := nil;
  Decl := ClassDeclAt(ATree, ALine);
  if Decl = nil then
  begin
    Exit;
  end;
  if PropertyAccessors(AText, ALine, AContext, Action) then
  begin
    Result := Result + [Action];
  end;
  for Name in TInterfaceStubs.HeaderAncestors(TTextLines.SplitLines(AText), Decl.StartPos.Line) do
  begin
    if TRegEx.IsMatch(Name, '^I[A-Z]') and ImplementInterface(AText, ALine, Name, AContext, Action) then
    begin
      Result := Result + [Action];
    end;
  end;
  Count := 0;
  for Name in OverrideCandidates(AText, ALine, AContext) do
  begin
    if Count >= MaxOverrides then
    begin
      Break;
    end;
    if OverrideMethod(AText, ALine, Name, AContext, Action) then
    begin
      Result := Result + [Action];
      Inc(Count);
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.ClassActions', cTexts);

end.
