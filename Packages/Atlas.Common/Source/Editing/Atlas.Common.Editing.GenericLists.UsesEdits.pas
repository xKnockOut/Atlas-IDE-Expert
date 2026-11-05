unit Atlas.Common.Editing.GenericLists.UsesEdits;

// uses-Listen einer Datei der Listenumwandlung (#1105, #1106): System.Generics.Collections kommt in das uses des
// Abschnitts, in dem der generische Typ steht (aus dem implementation-uses wandert es ins interface, wenn der Typ
// dort steht); Contnrs entfällt, wenn die Unit danach keinen Typ daraus mehr nennt. Listen mit Direktiven oder
// Kommentaren werden nur ergänzt, nie gekürzt.

interface

uses
  Atlas.Common.Editing.GenericLists.Kinds,
  Atlas.Common.Editing.GenericLists.Source;

type
  /// <summary>Edits der uses-Listen einer Datei.</summary>
  TGenericListUses = record
    /// <summary>Trägt die Edits der uses-Listen in ASource ein. ANamespaces sind die Namespaces des Projekts
    /// (System.Generics.Collections auch als Generics.Collections). False mit AReason, wenn die Unit nur im
    /// implementation-uses einer Liste mit Direktiven steht und ins interface müsste.</summary>
    class function AddEdits(ASource: TGenericListSource; const AKind: TLegacyListKind;
      const ANamespaces: TArray<string>; out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.GenericLists.Syntax,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TUsesEditsText = (IsOnlyInTheImplementation);

const
  cTexts: array[TUsesEditsText] of TAtlasText = (
    (De: '%s steht nur im implementation-uses (Liste mit Direktiven)';
     En: '%s is only in the implementation uses (list with directives)'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Ein Eintrag einer uses-Liste mit seinem Quelltext; Trennzeichen sind die Kommas.</summary>
  TUsesItem = record
    Name: string;
    Text: string;
    FirstToken: Integer;
    LastToken: Integer;
  end;

  /// <summary>Wo System.Generics.Collections gebraucht wird und schon steht.</summary>
  TUsesNeeds = record
    /// <summary>Der generische Typ steht irgendwo bzw. im interface.</summary>
    Generic: Boolean;
    InterfacePart: Boolean;
    /// <summary>System.Generics.Collections steht schon im interface- bzw. implementation-uses.</summary>
    UsedInInterface: Boolean;
    UsedInImplementation: Boolean;
    /// <summary>Contnrs entfällt.</summary>
    DropLegacy: Boolean;
    /// <summary>Aus dem implementation-uses ins interface verschieben.</summary>
    MoveGeneric: Boolean;
    /// <summary>In diesem Lauf eintragen.</summary>
    AddHere: Boolean;
  end;

  /// <summary>Rechnet die uses-Edits einer Datei aus.</summary>
  TUsesEditor = class
  private
    FSource: TGenericListSource;
    FKind: TLegacyListKind;
    FNamespaces: TArray<string>;
    FTokens: TArray<TPascalToken>;
    FClauses: TArray<TUsesClauseInfo>;
    FIsUnit: Boolean;
    FImplementationStart: Integer;
    FNeeds: TUsesNeeds;
    FTarget: Integer;
    FReason: string;
    function IsGenericUnit(const AName: string): Boolean;
    function IsDropped(const AClause: TUsesClauseInfo; const AName: string): Boolean;
    function InsertsGeneric(AIndex: Integer): Boolean;
    procedure FindNeeds;
    procedure NoteGenericUses(const AClause: TUsesClauseInfo);
    function TargetClause: Integer;
    function ParseItem(const AClause: TUsesClauseInfo; var ACursor: Integer): TUsesItem;
    function ParseItems(const AClause: TUsesClauseInfo): TArray<TUsesItem>;
    function KeptItems(const AClause: TUsesClauseInfo; const AItems: TArray<TUsesItem>;
      out AAddAt: Integer): TArray<TUsesItem>;
    function Separator(const AClause: TUsesClauseInfo; const AItems: TArray<TUsesItem>): string;
    procedure AddUnitTo(AOffset: Integer);
    procedure ReplaceItems(const AClause: TUsesClauseInfo; const AItems, AKept: TArray<TUsesItem>);
    procedure EditClause(AIndex: Integer);
    procedure AddClause;
  public
    constructor Create(ASource: TGenericListSource; const AKind: TLegacyListKind; const ANamespaces: TArray<string>);
    /// <summary>Alle Edits eintragen; False mit Reason.</summary>
    function Run: Boolean;
    property Reason: string read FReason;
  end;

{ TUsesEditor }

constructor TUsesEditor.Create(ASource: TGenericListSource; const AKind: TLegacyListKind;
  const ANamespaces: TArray<string>);
var
  mImplementation: TSyntaxNode;
begin
  inherited Create;
  FSource := ASource;
  FKind := AKind;
  FNamespaces := ANamespaces;
  FTokens := ASource.Tree.Tokens;
  FClauses := TUsesClauses.Clauses(FTokens);
  FIsUnit := ASource.Tree.Root.Kind = TSyntaxKind.UnitFile;
  mImplementation := ASource.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  FImplementationStart := MaxInt;
  if mImplementation <> nil then
  begin
    FImplementationStart := mImplementation.StartOffset;
  end;
end;

function TUsesEditor.IsGenericUnit(const AName: string): Boolean;
begin
  Result := TUsesClauses.IsUsed([AName], cGenericListUnit, FNamespaces);
end;

function TUsesEditor.IsDropped(const AClause: TUsesClauseInfo; const AName: string): Boolean;
begin
  Result := (FNeeds.DropLegacy and FKind.IsLegacyUnit(AName)) or
    (FNeeds.MoveGeneric and FIsUnit and not AClause.InInterface and IsGenericUnit(AName));
end;

function TUsesEditor.InsertsGeneric(AIndex: Integer): Boolean;
begin
  Result := (AIndex = FTarget) or (FNeeds.MoveGeneric and FClauses[AIndex].InInterface);
end;

procedure TUsesEditor.NoteGenericUses(const AClause: TUsesClauseInfo);
var
  mName: string;
begin
  for mName in AClause.Names do
  begin
    if not IsGenericUnit(mName) then
    begin
      Continue;
    end;
    if AClause.InInterface or not FIsUnit then
    begin
      FNeeds.UsedInInterface := True;
    end
    else
    begin
      FNeeds.UsedInImplementation := True;
    end;
  end;
end;

procedure TUsesEditor.FindNeeds;
var
  mOffset: Integer;
  mClause: TUsesClauseInfo;
begin
  FNeeds := Default(TUsesNeeds);
  FNeeds.Generic := FSource.GenericAt <> nil;
  for mOffset in FSource.GenericAt do
  begin
    FNeeds.InterfacePart := FNeeds.InterfacePart or (FIsUnit and (mOffset < FImplementationStart));
  end;
  for mClause in FClauses do
  begin
    NoteGenericUses(mClause);
  end;
  FNeeds.DropLegacy := SameText(FKind.LegacyUnit, 'Contnrs') and (FSource.Rewritten <> nil) and
    not FSource.LegacyUnitStillUsed;
  FNeeds.MoveGeneric := FNeeds.InterfacePart and FNeeds.UsedInImplementation and not FNeeds.UsedInInterface;
  FNeeds.AddHere := FNeeds.Generic and not FNeeds.UsedInInterface and
    not (FNeeds.UsedInImplementation and not FNeeds.InterfacePart);
end;

function TUsesEditor.TargetClause: Integer;
var
  mIndex: Integer;
begin
  // Zielliste für System.Generics.Collections: interface, wenn der Typ dort steht, sonst die des Abschnitts.
  Result := -1;
  if not FNeeds.AddHere then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FClauses) do
  begin
    if not FIsUnit or (FClauses[mIndex].InInterface = FNeeds.InterfacePart) then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TUsesEditor.ParseItem(const AClause: TUsesClauseInfo; var ACursor: Integer): TUsesItem;
var
  mToken: TPascalToken;
begin
  Result := Default(TUsesItem);
  Result.FirstToken := ACursor;
  Result.LastToken := ACursor;
  while (ACursor < AClause.Semicolon) and not FTokens[ACursor].IsSymbol(',') do
  begin
    mToken := FTokens[ACursor];
    if mToken.IsKeyword('in') then
    begin
      Result.Name := Result.Name + ' ';
    end
    else if (Pos(' ', Result.Name) = 0) and ((mToken.Kind = TPascalTokenKind.Identifier) or mToken.IsSymbol('.')) then
    begin
      Result.Name := Result.Name + mToken.Text;
    end;
    if not TGenericListSyntax.IsTrivia(mToken) then
    begin
      Result.LastToken := ACursor;
    end;
    Inc(ACursor);
  end;
  Result.Name := Trim(Result.Name);
  Result.Text := Copy(FSource.Text, FTokens[Result.FirstToken].Offset + 1, FTokens[Result.LastToken].Offset +
    Length(FTokens[Result.LastToken].Text) - FTokens[Result.FirstToken].Offset);
end;

function TUsesEditor.ParseItems(const AClause: TUsesClauseInfo): TArray<TUsesItem>;
var
  mCursor: Integer;
begin
  Result := nil;
  mCursor := AClause.UsesIndex + 1;
  while mCursor < AClause.Semicolon do
  begin
    while (mCursor < AClause.Semicolon) and TGenericListSyntax.IsTrivia(FTokens[mCursor]) do
    begin
      Inc(mCursor);
    end;
    if mCursor >= AClause.Semicolon then
    begin
      Break;
    end;
    Result := Result + [ParseItem(AClause, mCursor)];
    Inc(mCursor);
  end;
end;

function TUsesEditor.KeptItems(const AClause: TUsesClauseInfo; const AItems: TArray<TUsesItem>;
  out AAddAt: Integer): TArray<TUsesItem>;
var
  mItem: TUsesItem;
begin
  // AAddAt: Stelle des ersten entfernten Eintrags; dort kommt System.Generics.Collections hin.
  Result := nil;
  AAddAt := -1;
  for mItem in AItems do
  begin
    if not IsDropped(AClause, mItem.Name) then
    begin
      Result := Result + [mItem];
    end
    else if AAddAt < 0 then
    begin
      AAddAt := Length(Result);
    end;
  end;
end;

function TUsesEditor.Separator(const AClause: TUsesClauseInfo; const AItems: TArray<TUsesItem>): string;
begin
  if FTokens[AItems[High(AItems)].LastToken].StartPos.Line > FTokens[AClause.UsesIndex].StartPos.Line then
  begin
    Result := ',' + FSource.LineBreak + StringOfChar(' ', FTokens[AItems[0].FirstToken].StartPos.Character);
  end
  else
  begin
    Result := ', ';
  end;
end;

procedure TUsesEditor.AddUnitTo(AOffset: Integer);
var
  mEdit: TTextEdit;
begin
  if TUsesClauses.AddUnit(FTokens, AOffset, cGenericListUnit, FSource.LineBreak, mEdit) then
  begin
    FSource.AddTextEdit(mEdit);
  end;
end;

procedure TUsesEditor.ReplaceItems(const AClause: TUsesClauseInfo; const AItems, AKept: TArray<TUsesItem>);
var
  mItem: TUsesItem;
  mSeparator, mNewText: string;
begin
  if AKept = nil then
  begin
    FSource.AddEdit(FTokens[AClause.UsesIndex].StartPos, FTokens[AClause.Semicolon].EndPos, '');
    Exit;
  end;
  mSeparator := Separator(AClause, AItems);
  mNewText := '';
  for mItem in AKept do
  begin
    if mNewText <> '' then
    begin
      mNewText := mNewText + mSeparator;
    end;
    mNewText := mNewText + mItem.Text;
  end;
  FSource.AddEdit(FTokens[AItems[0].FirstToken].StartPos, FTokens[AItems[High(AItems)].LastToken].EndPos, mNewText);
end;

procedure TUsesEditor.EditClause(AIndex: Integer);
var
  mClause: TUsesClauseInfo;
  mItems, mKept: TArray<TUsesItem>;
  mGeneric: TUsesItem;
  mAddAt: Integer;
begin
  mClause := FClauses[AIndex];
  mItems := ParseItems(mClause);
  mKept := KeptItems(mClause, mItems, mAddAt);
  if (Length(mKept) <> Length(mItems)) and not mClause.Plain then
  begin
    // Listen mit Direktiven oder Kommentaren bleiben unangetastet; Contnrs bleibt dann stehen.
    if FNeeds.MoveGeneric then
    begin
      FReason := cTexts[TUsesEditsText.IsOnlyInTheImplementation].Fmt([cGenericListUnit]);
    end;
    mKept := mItems;
  end;
  if Length(mKept) = Length(mItems) then
  begin
    // Nichts entfernt: nur ergänzen, hinter den letzten Eintrag wie TUsesClauses.AddUnit.
    if InsertsGeneric(AIndex) then
    begin
      AddUnitTo(FTokens[mClause.UsesIndex].Offset + 1);
    end;
    Exit;
  end;
  if InsertsGeneric(AIndex) then
  begin
    mGeneric := Default(TUsesItem);
    mGeneric.Text := cGenericListUnit;
    Insert(mGeneric, mKept, mAddAt);
  end;
  ReplaceItems(mClause, mItems, mKept);
end;

procedure TUsesEditor.AddClause;
var
  mOffset, mIndex: Integer;
begin
  // Noch kein uses im Abschnitt: neues uses hinter interface bzw. implementation.
  mOffset := FSource.GenericAt[0];
  if FNeeds.InterfacePart then
  begin
    for mIndex := 0 to High(FSource.GenericAt) do
    begin
      if FSource.GenericAt[mIndex] < FImplementationStart then
      begin
        mOffset := FSource.GenericAt[mIndex];
        Break;
      end;
    end;
  end;
  AddUnitTo(mOffset);
end;

function TUsesEditor.Run: Boolean;
var
  mIndex: Integer;
begin
  FindNeeds;
  FTarget := TargetClause;
  for mIndex := 0 to High(FClauses) do
  begin
    EditClause(mIndex);
  end;
  if FNeeds.AddHere and (FTarget < 0) then
  begin
    AddClause;
  end;
  Result := FReason = '';
end;

{ TGenericListUses }

class function TGenericListUses.AddEdits(ASource: TGenericListSource; const AKind: TLegacyListKind;
  const ANamespaces: TArray<string>; out AReason: string): Boolean;
var
  mEditor: TUsesEditor;
begin
  mEditor := TUsesEditor.Create(ASource, AKind, ANamespaces);
  try
    Result := mEditor.Run;
    AReason := mEditor.Reason;
  finally
    mEditor.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.GenericLists.UsesEdits', cTexts);

end.
