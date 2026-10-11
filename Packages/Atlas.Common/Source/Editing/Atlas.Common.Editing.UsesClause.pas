unit Atlas.Common.Editing.UsesClause;

// uses-Listen lesen und ergänzen (#180), ohne Protokollbezug.
//
// - Rewrite (#284) schreibt die schlichten Listen neu: doppelte entfernen,
//   sortieren (alphabetisch oder nach Namespace gruppiert), Namen streichen.
//   Listen mit Direktiven ({$IFDEF}) oder //-Kommentaren bleiben unberührt.
//
// - Abschnitt: in einer Unit interface oder implementation, je nachdem, wo der
//   Cursor steht; in Programmen und Packages die uses nach dem Kopf.
// - Gibt es dort schon ein uses, kommt der Name vor dessen Semikolon; steht die
//   Liste über mehrere Zeilen, in eine eigene Zeile mit gleicher Einrückung.
//   Sonst entsteht hinter dem Abschnittswort ein neues uses.
// - Eine Unit gilt als eingebunden, wenn sie in einem der beiden uses steht,
//   auch ohne Namespace-Präfix (SysUtils für System.SysUtils, wenn "System"
//   zu den Namespaces des Projekts gehört).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Eintrag einer uses-, contains- oder requires-Liste mit Position (#183).</summary>
  TUsesReference = record
    Name: string;
    Range: TTextRange;
  end;

  /// <summary>Eine uses-Liste (#284).</summary>
  TUsesClauseInfo = record
    /// <summary>Token-Index von "uses" und vom abschließenden Semikolon.</summary>
    UsesIndex: Integer;
    Semicolon: Integer;
    Names: TArray<string>;
    /// <summary>Im interface einer Unit.</summary>
    InInterface: Boolean;
    /// <summary>Ohne Direktiven und //-Kommentare; nur solche Listen werden umgeschrieben.</summary>
    Plain: Boolean;
  end;

  /// <summary>Was Rewrite mit den Listen tut.</summary>
  TUsesRewrite = record
    Dedupe: Boolean;
    Sort: Boolean;
    /// <summary>Mit Sort: erst nach Namespace (System, Vcl, ...), Units ohne Namespace zuletzt.</summary>
    ByNamespace: Boolean;
    /// <summary>Diese Units entfallen.</summary>
    Drop: TArray<string>;
  end;

  TUsesClauses = class
  public
    /// <summary>Alle uses-Listen (nicht requires/contains) in Reihenfolge.</summary>
    class function Clauses(const ATokens: TArray<TPascalToken>): TArray<TUsesClauseInfo>; static;
    /// <summary>Schreibt die schlichten Listen nach AOptions um; False ohne Änderung.</summary>
    class function Rewrite(const ATokens: TArray<TPascalToken>; const AText: string; const AOptions: TUsesRewrite;
      const ALineBreak: string; out AEdits: TArray<TRuleEdit>): Boolean; static;
    /// <summary>Alle Unit-Namen aus den uses-Listen (interface und implementation).</summary>
    class function UsedUnits(const ATokens: TArray<TPascalToken>): TArray<string>; static;
    /// <summary>Alle Einträge aus uses, contains und requires mit Position, in Quelltextreihenfolge.</summary>
    class function References(const ATokens: TArray<TPascalToken>): TArray<TUsesReference>; static;
    /// <summary>Name der eigenen Unit bzw. des Programms; '' wenn unbekannt.</summary>
    class function OwnName(const ATokens: TArray<TPascalToken>): string; static;
    /// <summary>True, wenn AUnitName eingebunden ist, auch über einen der Namespaces.</summary>
    class function IsUsed(const AUsed: TArray<string>; const AUnitName: string;
      const ANamespaces: TArray<string>): Boolean; static;
    /// <summary>Edit, das AUnitName in das uses des Abschnitts an AOffset einträgt;
    /// False, wenn kein passender Abschnitt gefunden wird.</summary>
    class function AddUnit(const ATokens: TArray<TPascalToken>; AOffset: Integer; const AUnitName: string;
      const ALineBreak: string; out AEdit: TRuleEdit): Boolean; static;
    /// <summary>Räumt die uses-Listen auf (#182): doppelte Einträge entfernen, auch solche im
    /// implementation-uses, die schon im interface stehen; mit ASort alphabetisch sortieren.
    /// Listen mit Direktiven oder //-Kommentaren bleiben unangetastet. False ohne Änderung.</summary>
    class function Organize(const ATokens: TArray<TPascalToken>; const AText: string; ASort: Boolean;
      const ALineBreak: string; out AEdits: TArray<TRuleEdit>; AByNamespace: Boolean = False): Boolean; static;
  end;

implementation

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

/// <summary>Index des Semikolons, das die Anweisung ab AIndex abschließt; -1 ohne.</summary>
function SemicolonAfter(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while Result <= High(ATokens) do
  begin
    if ATokens[Result].IsSymbol(';') then
      Exit;
    Inc(Result);
  end;
  Result := -1;
end;

/// <summary>Erstes Token (nicht Trivia); -1 bei leerem Text.</summary>
function FirstIndex(const ATokens: TArray<TPascalToken>): Integer;
begin
  Result := NextIndex(ATokens, -1);
  if Result > High(ATokens) then
    Result := -1;
end;

/// <summary>Index des Abschnittsworts (interface/implementation) bzw. des Semikolons
/// hinter dem Programmkopf; -1, wenn nicht vorhanden.</summary>
function SectionStart(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  First, HeaderEnd, Index, Interface_, Implementation_: Integer;
begin
  Result := -1;
  First := FirstIndex(ATokens);
  if First < 0 then
    Exit;
  HeaderEnd := SemicolonAfter(ATokens, First);
  if HeaderEnd < 0 then
    Exit;
  if not ATokens[First].IsKeyword('unit') then
    // program, library, package: ein uses (bzw. contains) hinter dem Kopf.
    Exit(HeaderEnd);
  Interface_ := NextIndex(ATokens, HeaderEnd);
  if (Interface_ > High(ATokens)) or not ATokens[Interface_].IsKeyword('interface') then
    Exit;
  Implementation_ := -1;
  for Index := Interface_ + 1 to High(ATokens) do
    if ATokens[Index].IsKeyword('implementation') then
    begin
      Implementation_ := Index;
      Break;
    end;
  if (Implementation_ >= 0) and (AOffset >= ATokens[Implementation_].Offset) then
    Result := Implementation_
  else
    Result := Interface_;
end;

function ReadNames(const ATokens: TArray<TPascalToken>; AUses: Integer; var ANames: TArray<string>): Integer;
var
  Index: Integer;
  Name: string;
  AfterIn: Boolean;
begin
  // uses A, B.C in 'b.pas', D; liefert den Index des Semikolons.
  Index := AUses + 1;
  Name := '';
  AfterIn := False;
  while Index <= High(ATokens) do
  begin
    if ATokens[Index].IsSymbol(';') or ATokens[Index].IsSymbol(',') then
    begin
      if Name <> '' then
        ANames := ANames + [Name];
      Name := '';
      AfterIn := False;
      if ATokens[Index].IsSymbol(';') then
        Exit(Index);
    end
    else if ATokens[Index].IsKeyword('in') then
      AfterIn := True
    else if not AfterIn and ((ATokens[Index].Kind = TPascalTokenKind.Identifier) or ATokens[Index].IsSymbol('.')) then
      Name := Name + ATokens[Index].Text;
    Inc(Index);
  end;
  Result := -1;
end;

{ TUsesClauses }

class function TUsesClauses.UsedUnits(const ATokens: TArray<TPascalToken>): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  Index := 0;
  while Index <= High(ATokens) do
  begin
    if ATokens[Index].IsKeyword('uses') or ATokens[Index].IsKeyword('requires') then
    begin
      Index := ReadNames(ATokens, Index, Result);
      if Index < 0 then
        Exit;
    end;
    Inc(Index);
  end;
end;

/// <summary>True am Anfang einer uses-, contains- oder requires-Liste. contains und
/// requires sind keine reservierten Wörter, nur am Anweisungsanfang gemeint.</summary>
function IsListStart(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  Previous: Integer;
begin
  if ATokens[AIndex].IsKeyword('uses') or ATokens[AIndex].IsKeyword('requires') or
    ATokens[AIndex].IsKeyword('contains') then
    Exit(True);
  if not ((ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    (SameText(ATokens[AIndex].Text, 'contains') or SameText(ATokens[AIndex].Text, 'requires'))) then
    Exit(False);
  Previous := AIndex - 1;
  while (Previous >= 0) and IsTrivia(ATokens[Previous]) do
    Dec(Previous);
  Result := (Previous >= 0) and ATokens[Previous].IsSymbol(';');
end;

class function TUsesClauses.References(const ATokens: TArray<TPascalToken>): TArray<TUsesReference>;
var
  Index, First, Last: Integer;
  Name: string;
  AfterIn: Boolean;
  Reference: TUsesReference;
begin
  Result := nil;
  Index := 0;
  while Index <= High(ATokens) do
  begin
    if IsListStart(ATokens, Index) then
    begin
      // uses A, B.C in 'b.pas', D; ein Eintrag je Name, Position über alle Namensteile.
      Name := '';
      First := -1;
      Last := -1;
      AfterIn := False;
      Inc(Index);
      while Index <= High(ATokens) do
      begin
        if ATokens[Index].IsSymbol(';') or ATokens[Index].IsSymbol(',') then
        begin
          if Name <> '' then
          begin
            Reference.Name := Name;
            Reference.Range := TTextRange.Create(ATokens[First].StartPos, ATokens[Last].EndPos);
            Result := Result + [Reference];
          end;
          Name := '';
          First := -1;
          AfterIn := False;
          if ATokens[Index].IsSymbol(';') then
            Break;
        end
        else if ATokens[Index].IsKeyword('in') then
          AfterIn := True
        else if not AfterIn and ((ATokens[Index].Kind = TPascalTokenKind.Identifier) or
          ATokens[Index].IsSymbol('.')) then
        begin
          if First < 0 then
            First := Index;
          Last := Index;
          Name := Name + ATokens[Index].Text;
        end;
        Inc(Index);
      end;
    end;
    Inc(Index);
  end;
end;

class function TUsesClauses.OwnName(const ATokens: TArray<TPascalToken>): string;
var
  First, HeaderEnd, Index: Integer;
begin
  Result := '';
  First := FirstIndex(ATokens);
  if First < 0 then
    Exit;
  HeaderEnd := SemicolonAfter(ATokens, First);
  if HeaderEnd < 0 then
    Exit;
  for Index := First + 1 to HeaderEnd - 1 do
    if (ATokens[Index].Kind = TPascalTokenKind.Identifier) or ATokens[Index].IsSymbol('.') then
      Result := Result + ATokens[Index].Text
    else if not IsTrivia(ATokens[Index]) then
      Break;
end;

class function TUsesClauses.IsUsed(const AUsed: TArray<string>; const AUnitName: string;
  const ANamespaces: TArray<string>): Boolean;
var
  Used, Namespace: string;
begin
  for Used in AUsed do
  begin
    if SameText(Used, AUnitName) then
      Exit(True);
    for Namespace in ANamespaces do
      if SameText(Namespace + '.' + Used, AUnitName) then
        Exit(True);
  end;
  Result := False;
end;

type
  TUsesItem = record
    Name: string;
    Text: string;
    Order: Integer;
  end;

function TokenEnd(const AToken: TPascalToken): Integer;
begin
  Result := AToken.Offset + Length(AToken.Text);
end;

/// <summary>Sortierschlüssel der Gruppe: Namespace, Units ohne Namespace zuletzt.</summary>
function GroupOf(const AName: string): string;
var
  Dot: Integer;
begin
  Dot := Pos('.', AName);
  if Dot = 0 then
    Result := #$FFFF
  else
    Result := Copy(AName, 1, Dot - 1);
end;

function ItemLess(const A, B: TUsesItem; AByNamespace: Boolean): Boolean;
var
  Compared: Integer;
begin
  Compared := 0;
  if AByNamespace then
    Compared := CompareText(GroupOf(A.Name), GroupOf(B.Name));
  if Compared = 0 then
    Compared := CompareText(A.Name, B.Name);
  Result := (Compared < 0) or ((Compared = 0) and (A.Order < B.Order));
end;

/// <summary>Stabiles Sortieren durch Einfügen; uses-Listen sind kurz.</summary>
procedure SortItems(var AItems: TArray<TUsesItem>; AByNamespace: Boolean);
var
  I, J: Integer;
  Item: TUsesItem;
begin
  for I := 1 to High(AItems) do
  begin
    Item := AItems[I];
    J := I - 1;
    while (J >= 0) and ItemLess(Item, AItems[J], AByNamespace) do
    begin
      AItems[J + 1] := AItems[J];
      Dec(J);
    end;
    AItems[J + 1] := Item;
  end;
end;

function ContainsName(const ANames: TArray<string>; const AName: string): Boolean;
var
  Name: string;
begin
  for Name in ANames do
    if SameText(Name, AName) then
      Exit(True);
  Result := False;
end;

/// <summary>True, wenn die Liste zwischen AFirst und ALast keine Direktive und keinen //-Kommentar enthält.</summary>
function IsPlainList(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Boolean;
var
  Index: Integer;
begin
  for Index := AFirst to ALast do
    if (ATokens[Index].Kind = TPascalTokenKind.Directive) or
      ((ATokens[Index].Kind = TPascalTokenKind.Comment) and (Copy(ATokens[Index].Text, 1, 2) = '//')) then
      Exit(False);
  Result := True;
end;

class function TUsesClauses.Clauses(const ATokens: TArray<TPascalToken>): TArray<TUsesClauseInfo>;
var
  Index: Integer;
  IsUnit, InImplementation: Boolean;
  Clause: TUsesClauseInfo;
begin
  Result := nil;
  Index := FirstIndex(ATokens);
  IsUnit := (Index >= 0) and ATokens[Index].IsKeyword('unit');
  InImplementation := False;
  Index := 0;
  while Index <= High(ATokens) do
  begin
    if ATokens[Index].IsKeyword('implementation') then
      InImplementation := True
    else if ATokens[Index].IsKeyword('uses') then
    begin
      Clause.UsesIndex := Index;
      Clause.Names := nil;
      Clause.Semicolon := ReadNames(ATokens, Index, Clause.Names);
      if Clause.Semicolon < 0 then
        Exit;
      Clause.InInterface := IsUnit and not InImplementation;
      Clause.Plain := IsPlainList(ATokens, Index + 1, Clause.Semicolon - 1);
      Result := Result + [Clause];
      Index := Clause.Semicolon;
    end;
    Inc(Index);
  end;
end;

class function TUsesClauses.Organize(const ATokens: TArray<TPascalToken>; const AText: string; ASort: Boolean;
  const ALineBreak: string; out AEdits: TArray<TRuleEdit>; AByNamespace: Boolean): Boolean;
var
  Options: TUsesRewrite;
begin
  Options := Default(TUsesRewrite);
  Options.Dedupe := True;
  Options.Sort := ASort;
  Options.ByNamespace := AByNamespace;
  Result := Rewrite(ATokens, AText, Options, ALineBreak, AEdits);
end;

class function TUsesClauses.Rewrite(const ATokens: TArray<TPascalToken>; const AText: string;
  const AOptions: TUsesRewrite; const ALineBreak: string; out AEdits: TArray<TRuleEdit>): Boolean;
var
  Index, Semicolon, Cursor, First, Last, ItemIndex: Integer;
  Seen: TArray<string>;
  Items, Kept: TArray<TUsesItem>;
  Item: TUsesItem;
  Changed, AfterIn: Boolean;
  Separator, NewText: string;
  Names: TArray<string>;
begin
  AEdits := nil;
  Seen := nil;
  Index := 0;
  while Index <= High(ATokens) do
  begin
    if not ATokens[Index].IsKeyword('uses') then
    begin
      Inc(Index);
      Continue;
    end;
    Names := nil;
    Semicolon := ReadNames(ATokens, Index, Names);
    if Semicolon < 0 then
      Break;
    if not IsPlainList(ATokens, Index + 1, Semicolon - 1) then
    begin
      // Unangetastet, aber die Namen zählen für spätere Listen.
      Seen := Seen + Names;
      Index := Semicolon + 1;
      Continue;
    end;
    // Einträge mit ihrem Quelltext, Trennzeichen sind die Kommas.
    Items := nil;
    Cursor := NextIndex(ATokens, Index);
    while Cursor < Semicolon do
    begin
      First := Cursor;
      Last := Cursor;
      Item.Name := '';
      AfterIn := False;
      while (Cursor < Semicolon) and not ATokens[Cursor].IsSymbol(',') do
      begin
        if ATokens[Cursor].IsKeyword('in') then
          AfterIn := True
        else if not AfterIn and ((ATokens[Cursor].Kind = TPascalTokenKind.Identifier) or
          ATokens[Cursor].IsSymbol('.')) then
          Item.Name := Item.Name + ATokens[Cursor].Text;
        Last := Cursor;
        Inc(Cursor);
      end;
      Item.Text := Copy(AText, ATokens[First].Offset + 1, TokenEnd(ATokens[Last]) - ATokens[First].Offset);
      Item.Order := Length(Items);
      Items := Items + [Item];
      if Cursor < Semicolon then
        Cursor := NextIndex(ATokens, Cursor);
    end;
    if Items = nil then
    begin
      Index := Semicolon + 1;
      Continue;
    end;
    Kept := nil;
    for Item in Items do
      if not ContainsName(AOptions.Drop, Item.Name) and not (AOptions.Dedupe and ContainsName(Seen, Item.Name)) then
      begin
        Kept := Kept + [Item];
        Seen := Seen + [Item.Name];
      end;
    if AOptions.Sort then
      SortItems(Kept, AOptions.ByNamespace);
    Changed := Length(Kept) <> Length(Items);
    for ItemIndex := 0 to High(Kept) do
      if Kept[ItemIndex].Order <> ItemIndex then
        Changed := True;
    if Changed then
    begin
      First := NextIndex(ATokens, Index);
      // Bis zum Semikolon, damit ein Kommentar am letzten Eintrag nicht doppelt erscheint.
      Last := Semicolon - 1;
      if Kept = nil then
        AEdits := AEdits + [TRuleEdit.Create(TTextRange.Create(ATokens[Index].StartPos, ATokens[Semicolon].EndPos), '')]
      else
      begin
        if ATokens[Last].StartPos.Line > ATokens[Index].StartPos.Line then
          Separator := ',' + ALineBreak + StringOfChar(' ', ATokens[First].StartPos.Character)
        else
          Separator := ', ';
        NewText := '';
        for ItemIndex := 0 to High(Kept) do
        begin
          if ItemIndex > 0 then
            NewText := NewText + Separator;
          NewText := NewText + Kept[ItemIndex].Text;
        end;
        AEdits := AEdits + [TRuleEdit.Create(TTextRange.Create(ATokens[First].StartPos, ATokens[Last].EndPos),
          NewText)];
      end;
    end;
    Index := Semicolon + 1;
  end;
  Result := AEdits <> nil;
end;

class function TUsesClauses.AddUnit(const ATokens: TArray<TPascalToken>; AOffset: Integer;
  const AUnitName, ALineBreak: string; out AEdit: TRuleEdit): Boolean;
var
  Start, UsesIndex, Semicolon, LastName: Integer;
  Names: TArray<string>;
  Indent: string;
begin
  Start := SectionStart(ATokens, AOffset);
  if Start < 0 then
    Exit(False);
  UsesIndex := NextIndex(ATokens, Start);
  if (UsesIndex <= High(ATokens)) and (ATokens[UsesIndex].IsKeyword('uses')) then
  begin
    Names := nil;
    Semicolon := ReadNames(ATokens, UsesIndex, Names);
    if Semicolon < 0 then
      Exit(False);
    LastName := Semicolon - 1;
    while (LastName > UsesIndex) and IsTrivia(ATokens[LastName]) do
      Dec(LastName);
    if ATokens[LastName].StartPos.Line > ATokens[UsesIndex].StartPos.Line then
    begin
      // Mehrzeilige Liste: eigene Zeile, eingerückt wie die Zeile des letzten Eintrags.
      while (LastName > UsesIndex) and (ATokens[LastName - 1].StartPos.Line = ATokens[LastName].StartPos.Line) do
        Dec(LastName);
      Indent := StringOfChar(' ', ATokens[LastName].StartPos.Character);
      AEdit := TRuleEdit.Create(TTextRange.Create(ATokens[Semicolon].StartPos, ATokens[Semicolon].StartPos),
        ',' + ALineBreak + Indent + AUnitName);
    end
    else
      AEdit := TRuleEdit.Create(TTextRange.Create(ATokens[Semicolon].StartPos, ATokens[Semicolon].StartPos),
        ', ' + AUnitName);
    Exit(True);
  end;
  AEdit := TRuleEdit.Create(TTextRange.Create(ATokens[Start].EndPos, ATokens[Start].EndPos),
    ALineBreak + ALineBreak + 'uses' + ALineBreak + '  ' + AUnitName + ';');
  Result := True;
end;

end.
