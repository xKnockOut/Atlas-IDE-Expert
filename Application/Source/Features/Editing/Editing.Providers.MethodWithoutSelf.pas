unit Editing.Providers.MethodWithoutSelf;

// IEditingMethodsWithoutSelf über TMethodWithoutSelf: arbeitet auf dem Baum des Aufrufers, löst Mitglieder über
// einen eigenen TNameResolver auf und bietet je Methode die Umwandlung in eine class-Methode an. Aufrufe über
// Instanzen bleiben gültig, darum ändert sie nur die Unit selbst.

interface

uses
  Editing.Contract.MethodWithoutSelf;

type
  TEditingMethodsWithoutSelfProvider = class(TInterfacedObject, IEditingMethodsWithoutSelf)
  public
    function Scan(const AScan: TEditingMethodScan): TArray<TEditingMethodWithoutSelf>;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeHandles,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Pascal.EventAssignments,
  Atlas.Common.Semantics.NameResolver,
  Editing.MethodWithoutSelf,
  Editing.MethodWithoutSelf.Types,
  Editing.MethodWithoutSelf.Lookup,
  Editing.PromoteVariable;

/// <summary>Steht AName als ganzes Wort (ohne Groß-/Kleinschreibung) in AText?</summary>
function MentionsWord(const AText, AName: string): Boolean;
var
  mPosition: Integer;
  mBefore, mAfter: Char;
begin
  Result := False;
  mPosition := Pos(UpperCase(AName), UpperCase(AText));
  while mPosition > 0 do
  begin
    mBefore := ' ';
    mAfter := ' ';
    if mPosition > 1 then
    begin
      mBefore := AText[mPosition - 1];
    end;
    if mPosition + Length(AName) <= Length(AText) then
    begin
      mAfter := AText[mPosition + Length(AName)];
    end;
    if not CharInSet(mBefore, ['A'..'Z', 'a'..'z', '0'..'9', '_']) and
      not CharInSet(mAfter, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      Exit(True);
    end;
    mPosition := Pos(UpperCase(AName), UpperCase(AText), mPosition + 1);
  end;
end;

/// <summary>Ist AName ein Ereignis der Formulardatei AFormText oder wird es in ATree einem Ereignis zugewiesen?
/// </summary>
function EventCheck(const AFormText: string; ATree: TSyntaxTree): TPromoteInFormFunc;
var
  mAssigned: TArray<string>;
begin
  mAssigned := TEventAssignments.Names(ATree.Tokens);
  Result :=
    function(const AName: string): Boolean
    begin
      Result := MentionsWord(AFormText, AName) or (IndexText(AName, mAssigned) >= 0);
    end;
end;

/// <summary>Umwandlung von ATarget in eine class-Methode, nur die Änderungen in AScan.FileName.</summary>
function ClassMethodFix(const AScan: TEditingMethodScan; ATree: TSyntaxTree; const ATarget: TMethodTarget;
  const ALookup: TMethodLookup; out AFix: TCodeAction): Boolean;
var
  mConverted: TMethodResult;
  mReason: string;
  mItem: TMethodFileEdits;
begin
  Result := False;
  AFix := Default(TCodeAction);
  if not TMethodWithoutSelf.Execute(TMethodSource.Create(AScan.FileName, AScan.Text, ATree,
    NameUseOffsets(ATree.Tokens, ATarget.Name)), nil, TMethodRequest.Create(ATarget.NamePosition,
    TMethodConversion.ClassMethod, AScan.WithStatic, ALookup, AScan.Style), mConverted, mReason) then
  begin
    Exit;
  end;
  for mItem in mConverted.Files do
  begin
    if SameText(mItem.FileName, AScan.FileName) and (mItem.Edits <> nil) then
    begin
      AFix.Title := TMethodWithoutSelf.ClassMethodTitle;
      AFix.Edits := mItem.Edits;
      Result := True;
    end;
  end;
end;

{ TEditingMethodsWithoutSelfProvider }

function TEditingMethodsWithoutSelfProvider.Scan(const AScan: TEditingMethodScan): TArray<TEditingMethodWithoutSelf>;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mLookup: TMethodLookup;
  mTarget: TMethodTarget;
  mItem: TEditingMethodWithoutSelf;
begin
  Result := nil;
  mTree := TSyntaxTreeHandles.TreeOf(AScan.Tree);
  if (mTree = nil) or (mTree.Root = nil) then
  begin
    Exit;
  end;
  mResolver := TNameResolver.Create(AScan.Index, AScan.EnsureUnit);
  try
    mResolver.Namespaces := AScan.Namespaces;
    mResolver.PinTree(mTree, AScan.FileName);
    try
      mLookup := TMethodLookup.FromResolver(mResolver, mTree, AScan.FileName);
      // Ereignisse der Formulardatei und im Code zugewiesene Ereignisse brauchen eine Methode des Objekts.
      mLookup.InForm := EventCheck(AScan.FormText, mTree);
      for mTarget in TMethodWithoutSelf.Candidates(AScan.Text, mTree, mLookup) do
      begin
        mItem := Default(TEditingMethodWithoutSelf);
        mItem.ClassName := mTarget.ClassName;
        mItem.Name := mTarget.Name;
        mItem.NamePosition := mTarget.NamePosition;
        mItem.HasFix := ClassMethodFix(AScan, mTree, mTarget, mLookup, mItem.Fix);
        Result := Result + [mItem];
      end;
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
  end;
end;

end.
