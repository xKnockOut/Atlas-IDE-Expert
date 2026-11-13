unit Atlas.Common.Leaks.Internals.OwnershipTree;

// Hilfen über dem Syntaxbaum für „Wer gibt das frei?“ (#1877, Atlas.Common.Leaks.Ownership): Routine und Klasse um
// eine Stelle, lokale Variablen und Parameter, Felder einer Klasse, Vorkommen eines Namens, Freigaben und
// finally-Blöcke. Ohne Zustand.

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
{$SCOPEDENUMS ON}
  /// <summary>Was ein Name in einer Routine ist.</summary>
  TOwnershipNameKind = (Unknown, Local, Parameter, OutParameter, Field, ResultValue);
{$SCOPEDENUMS OFF}

  TOwnershipTree = class
  public const
    /// <summary>Methoden, die das Objekt freigeben.</summary>
    cReleaseMembers: array[0..3] of string = ('Free', 'Destroy', 'DisposeOf', 'Release');
  public
    /// <summary>Innerste Routine um ANode; nil außerhalb.</summary>
    class function RoutineOf(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Klasse einer Methode TKlasse.Name (auch TAussen.TInnen.Name); '' bei freien Routinen.</summary>
    class function ClassOf(ARoutine: TSyntaxNode): string; static;
    /// <summary>Methoden der Klasse AClassName mit Rumpf, ohne Methoden verschachtelter Klassen.</summary>
    class function MethodsOf(ARoot: TSyntaxNode; const AClassName: string): TArray<TSyntaxNode>; static;
    /// <summary>Was AName in ARoutine ist; ATypeName ist der deklarierte Typ ('' ohne Angabe).</summary>
    class function NameKind(ARoot, ARoutine: TSyntaxNode; const AName: string; out ATypeName: string):
      TOwnershipNameKind; static;
    /// <summary>Typ des Felds AField der Klasse AClassName in der Datei; False ohne.</summary>
    class function FieldType(ARoot: TSyntaxNode; const AClassName, AField: string; out ATypeName: string): Boolean;
      static;
    /// <summary>Name hinter X bzw. Self.X; '' sonst.</summary>
    class function SelfMemberName(ANode: TSyntaxNode): string; static;
    /// <summary>Vorkommen von AName (auch Self.AName) unter ANode, ohne Mitglieder anderer Objekte (Obj.AName).
    /// </summary>
    class function Occurrences(ANode: TSyntaxNode; const AName: string): TArray<TSyntaxNode>; static;
    /// <summary>Gibt das Vorkommen ANode das Objekt frei (X.Free, X.Destroy, X.DisposeOf, X.Release,
    /// FreeAndNil(X))?</summary>
    class function IsRelease(ANode: TSyntaxNode): Boolean; static;
    /// <summary>Steht ANode im finally-Teil eines try unterhalb von AStop?</summary>
    class function InFinally(ANode, AStop: TSyntaxNode): Boolean; static;
    /// <summary>Steht ANode in einer raise-Anweisung?</summary>
    class function InRaise(ANode: TSyntaxNode): Boolean; static;
    /// <summary>Folgt AName der Namensregel für Interfaces (IName, auch Unit.IName, IList&lt;T&gt;)?</summary>
    class function LooksLikeInterface(const AName: string): Boolean; static;
    /// <summary>Elementtyp eines generischen Typs: TFoo bei TObjectList&lt;TFoo&gt;; '' ohne.</summary>
    class function ElementType(const ATypeName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Editing.RoutineBody;

class function TOwnershipTree.RoutineOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    Result := Result.Parent;
  end;
end;

class function TOwnershipTree.ClassOf(ARoutine: TSyntaxNode): string;
var
  mAt: Integer;
begin
  Result := '';
  if ARoutine = nil then
  begin
    Exit;
  end;
  mAt := ARoutine.Name.LastIndexOf('.');
  if mAt > 0 then
  begin
    Result := Copy(ARoutine.Name, 1, mAt);
  end;
end;

class function TOwnershipTree.MethodsOf(ARoot: TSyntaxNode; const AClassName: string): TArray<TSyntaxNode>;
var
  mSection: TSyntaxNode;
  mIndex: Integer;
  mDecl: TSyntaxNode;
  mRest: string;
begin
  Result := nil;
  mSection := ARoot.FindChild(TSyntaxKind.ImplementationSection);
  if (mSection = nil) or (AClassName = '') then
  begin
    Exit;
  end;
  for mIndex := 0 to mSection.ChildCount - 1 do
  begin
    mDecl := mSection[mIndex];
    if (mDecl.Kind = TSyntaxKind.RoutineDecl) and StartsText(AClassName + '.', mDecl.Name) and
      (TRoutineBody.BodyOf(mDecl) <> nil) then
    begin
      mRest := Copy(mDecl.Name, Length(AClassName) + 2, MaxInt);
      if (mRest <> '') and (Pos('.', mRest) = 0) then
      begin
        Result := Result + [mDecl];
      end;
    end;
  end;
end;

/// <summary>Typ einer Deklaration (VarDecl, InlineVar, Parameter, Field); '' ohne Typangabe.</summary>
function DeclaredType(ADecl: TSyntaxNode): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to ADecl.ChildCount - 1 do
  begin
    if ADecl[mIndex].Kind = TSyntaxKind.TypeReference then
    begin
      Exit(ADecl[mIndex].Name);
    end;
  end;
end;

/// <summary>Nennt die Deklaration ADecl ("A, B") den Namen AName?</summary>
function Declares(ADecl: TSyntaxNode; const AName: string): Boolean;
var
  mName: string;
begin
  for mName in ADecl.Name.Split([',']) do
  begin
    if SameText(Trim(mName), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Deklaration von AName im var-Abschnitt, unter den Parametern oder als Inline-Variable von ARoutine.
/// </summary>
function FindDeclaration(ARoutine: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mRoutine: TSyntaxNode;
  mName: string;
begin
  // Kopien: Methodenreferenzen fangen keine Parameter ein.
  mRoutine := ARoutine;
  mName := AName;
  Result := ARoutine.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode <> mRoutine) and (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Parameter, TSyntaxKind.InlineVar]) and
        Declares(ANode, mName) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

class function TOwnershipTree.NameKind(ARoot, ARoutine: TSyntaxNode; const AName: string;
  out ATypeName: string): TOwnershipNameKind;
var
  mDecl: TSyntaxNode;
begin
  ATypeName := '';
  if SameText(AName, 'Result') then
  begin
    Exit(TOwnershipNameKind.ResultValue);
  end;
  Result := TOwnershipNameKind.Unknown;
  if ARoutine = nil then
  begin
    Exit;
  end;
  mDecl := FindDeclaration(ARoutine, AName);
  if mDecl <> nil then
  begin
    ATypeName := DeclaredType(mDecl);
    Result := TOwnershipNameKind.Local;
    if mDecl.Kind = TSyntaxKind.Parameter then
    begin
      Result := TOwnershipNameKind.Parameter;
      if mDecl.Modifier in [TParameterModifier.OutParam, TParameterModifier.VarParam] then
      begin
        Result := TOwnershipNameKind.OutParameter;
      end;
    end;
  end
  else if FieldType(ARoot, ClassOf(ARoutine), AName, ATypeName) then
  begin
    Result := TOwnershipNameKind.Field;
  end;
end;

class function TOwnershipTree.FieldType(ARoot: TSyntaxNode; const AClassName, AField: string;
  out ATypeName: string): Boolean;
var
  mBody, mField: TSyntaxNode;
  mShort, mFieldName: string;
begin
  ATypeName := '';
  mShort := TRoutineBody.ShortNameOf(AClassName);
  mFieldName := AField;
  if (AClassName = '') or (AField = '') then
  begin
    Exit(False);
  end;
  mBody := TRoutineBody.TypeBody(ARoot, mShort);
  if mBody = nil then
  begin
    Exit(False);
  end;
  mField := mBody.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind = TSyntaxKind.TypeDecl then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind = TSyntaxKind.Field) and Declares(ANode, mFieldName) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
  Result := mField <> nil;
  if Result then
  begin
    ATypeName := DeclaredType(mField);
  end;
end;

class function TOwnershipTree.SelfMemberName(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode = nil then
  begin
    Exit;
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := ANode.Name;
  end
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
  begin
    Result := ANode.Name;
  end;
end;

/// <summary>Ist ANode der Name AName selbst, nicht das Mitglied eines anderen Objekts?</summary>
function IsOccurrence(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := SameText(ANode.Name, AName) and not ((ANode.Parent <> nil) and
      (ANode.Parent.Kind = TSyntaxKind.MemberAccess) and (ANode.Parent[0] <> ANode));
  end
  else
  begin
    Result := (ANode.Kind = TSyntaxKind.MemberAccess) and
      SameText(TOwnershipTree.SelfMemberName(ANode), AName) and (ANode.ChildCount = 1);
  end;
end;

class function TOwnershipTree.Occurrences(ANode: TSyntaxNode; const AName: string): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
  mName: string;
begin
  mFound := nil;
  mName := AName;
  if ANode <> nil then
  begin
    ANode.Walk(
      function(AChild: TSyntaxNode): Boolean
      begin
        Result := True;
        if IsOccurrence(AChild, mName) then
        begin
          mFound := mFound + [AChild];
          // Self.X: das Self darunter ist kein weiteres Vorkommen.
          Result := False;
        end;
      end);
  end;
  Result := mFound;
end;

class function TOwnershipTree.IsRelease(ANode: TSyntaxNode): Boolean;
var
  mParent: TSyntaxNode;
begin
  mParent := ANode.Parent;
  Result := False;
  if mParent = nil then
  begin
    Exit;
  end;
  if (mParent.Kind = TSyntaxKind.MemberAccess) and (mParent[0] = ANode) then
  begin
    Result := MatchText(mParent.Name, cReleaseMembers);
  end
  else if (mParent.Kind = TSyntaxKind.Call) and (mParent.ChildCount = 2) and (mParent[1] = ANode) and
    (mParent[0].Kind = TSyntaxKind.Identifier) then
  begin
    Result := SameText(mParent[0].Name, 'FreeAndNil');
  end;
end;

class function TOwnershipTree.InFinally(ANode, AStop: TSyntaxNode): Boolean;
var
  mCurrent: TSyntaxNode;
begin
  mCurrent := ANode;
  while (mCurrent <> nil) and (mCurrent <> AStop) do
  begin
    if mCurrent.Kind = TSyntaxKind.FinallyBlock then
    begin
      Exit(True);
    end;
    mCurrent := mCurrent.Parent;
  end;
  Result := False;
end;

class function TOwnershipTree.InRaise(ANode: TSyntaxNode): Boolean;
var
  mCurrent: TSyntaxNode;
begin
  mCurrent := ANode;
  while (mCurrent <> nil) and (mCurrent.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    if mCurrent.Kind = TSyntaxKind.RaiseStatement then
    begin
      Exit(True);
    end;
    mCurrent := mCurrent.Parent;
  end;
  Result := False;
end;

class function TOwnershipTree.LooksLikeInterface(const AName: string): Boolean;
var
  mName: string;
begin
  mName := AName;
  if Pos('<', mName) > 0 then
  begin
    mName := Copy(mName, 1, Pos('<', mName) - 1);
  end;
  if mName.Contains('.') then
  begin
    mName := Copy(mName, mName.LastIndexOf('.') + 2, MaxInt);
  end;
  Result := (Length(mName) > 1) and (mName[1] = 'I') and CharInSet(mName[2], ['A'..'Z']);
end;

class function TOwnershipTree.ElementType(const ATypeName: string): string;
var
  mOpen, mClose: Integer;
begin
  Result := '';
  mOpen := Pos('<', ATypeName);
  mClose := LastDelimiter('>', ATypeName);
  if (mOpen > 0) and (mClose > mOpen) then
  begin
    Result := Trim(Copy(ATypeName, mOpen + 1, mClose - mOpen - 1));
  end;
end;

end.
