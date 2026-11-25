unit Atlas.Common.Pascal.ObjectUses;

// Wie ein Objekt an einer Stelle vorkommt, vom Bezeichner nach oben bis zur
// Anweisung eingeordnet. Gemeinsam für die Leckregel local-object-not-freed
// (lokale Variablen) und die Zusammenfassung je Parameter im Index (was eine
// Routine mit einem übergebenen Objekt macht, Atlas.Common.Pascal.ParamOwnership):
//   Use        nur gelesen: Mitglied aufgerufen, verglichen, an eine lesende Routine übergeben
//   Assigned   links von := (neu belegt); Anweisung in Node
//   Release    freigegeben: Free, Destroy, DisposeOf, Release, FreeAndNil und Routinen mit
//              Free/Release/Destroy/Dispose im Namen
//   Escape     verlässt die Routine bzw. geht an einen neuen Besitzer: rechts von :=, Exit(X), raise X,
//              X as I, @X, [X], with X, X.Parent := …, Show/Start/Execute (verwaltet sich selbst)
//   Argument   als Argument an einen Aufruf, der weder freigibt noch nur liest; Aufruf in Node, Stelle des
//              Arguments (ab 0) in Argument. Was die Routine damit macht, klärt der Aufrufer (Index).
// Typumwandlungen wie TFoo(X) und Klammern zählen nicht.

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
{$SCOPEDENUMS ON}
  TObjectUseKind = (Use, Assigned, Release, Escape, Argument);
{$SCOPEDENUMS OFF}

  TObjectUse = record
    Kind: TObjectUseKind;
    /// <summary>Bei Assigned die Zuweisung, bei Argument der Aufruf; sonst nil.</summary>
    Node: TSyntaxNode;
    /// <summary>Bei Argument die Stelle des Arguments ab 0; sonst -1.</summary>
    Argument: Integer;
  end;

  TObjectUses = class
  public const
    /// <summary>Routinen, die ein Objekt als Argument nur lesen und nicht behalten.</summary>
    cReadingCalls: array[0..8] of string = ('Assigned', 'Assign', 'AddStrings', 'CopyFrom', 'LoadFromStream',
      'SaveToStream', 'IndexOf', 'Contains', 'Equals');
    /// <summary>Teile eines Routinennamens, die auf eine Freigaberoutine schließen lassen.</summary>
    cReleaseWords: array[0..4] of string = ('Free', 'Release', 'Destroy', 'Dispose', 'Frei');
  public
    /// <summary>Art des Vorkommens ANode (Bezeichner des Objekts) vom Knoten aus nach oben.</summary>
    class function Classify(ANode: TSyntaxNode): TObjectUse; static;
    /// <summary>Typumwandlung wie TFoo(X) oder IFoo(X): ein Argument, Aufruf über einen Typnamen.</summary>
    class function IsTypeCast(ACall: TSyntaxNode): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Names,
  Atlas.Text.Arrays,
  Atlas.Common.Pascal.SyntaxNodes;

const
  // Methoden des Objekts, die es freigeben.
  cReleaseMembers: array[0..4] of string = ('Free', 'Destroy', 'DisposeOf', 'Release', 'FreeInstance');
  // Methoden, nach denen das Objekt sich selbst verwaltet (Formular mit caFree, Thread).
  cSelfManagingMembers: array[0..5] of string = ('Show', 'Close', 'Start', 'Resume', 'Run', 'Execute');
  // Properties, deren Zuweisung den Besitz übergibt bzw. die Freigabe regelt.
  cOwningProperties: array[0..2] of string = ('Parent', 'Owner', 'FreeOnTerminate');

function NewUse(AKind: TObjectUseKind; ANode: TSyntaxNode; AArgument: Integer): TObjectUse;
begin
  Result.Kind := AKind;
  Result.Node := ANode;
  Result.Argument := AArgument;
end;

/// <summary>Folgt AName der Namensregel für Typen (TName)?</summary>
function LooksLikeType(const AName: string): Boolean;
begin
  Result := (Length(AName) > 1) and (AName[1] = 'T') and CharInSet(AName[2], ['A'..'Z']);
end;

/// <summary>Vorkommen als Objekt eines Mitgliedszugriffs X.Name.</summary>
function UseInMember(AAccess: TSyntaxNode): TObjectUseKind;
var
  mParent: TSyntaxNode;
begin
  Result := TObjectUseKind.Use;
  mParent := AAccess.Parent;
  if MatchText(AAccess.Name, cReleaseMembers) then
  begin
    Result := TObjectUseKind.Release;
  end
  else if MatchText(AAccess.Name, cSelfManagingMembers) then
  begin
    Result := TObjectUseKind.Escape;
  end
  else if (mParent <> nil) and (mParent.Kind = TSyntaxKind.AssignStatement) and (mParent[0] = AAccess) and
    MatchText(AAccess.Name, cOwningProperties) then
  begin
    Result := TObjectUseKind.Escape;
  end;
end;

/// <summary>Vorkommen ACurrent als Teil des Aufrufs ACall; False bei einer Typumwandlung (weiter nach oben).
/// </summary>
function UseInCall(ACall, ACurrent: TSyntaxNode; var AUse: TObjectUse): Boolean;
begin
  Result := True;
  if ACall[0] = ACurrent then
  begin
    AUse.Kind := TObjectUseKind.Use;
  end
  else if TTextArrays.ContainsAnyText(ACall.Name, TObjectUses.cReleaseWords) then
  begin
    AUse.Kind := TObjectUseKind.Release;
  end
  else if MatchText(ACall.Name, TObjectUses.cReadingCalls) then
  begin
    AUse.Kind := TObjectUseKind.Use;
  end
  else if TObjectUses.IsTypeCast(ACall) then
  begin
    Result := False;
  end
  else if SameText(ACall.Name, 'Exit') then
  begin
    AUse.Kind := TObjectUseKind.Escape;
  end
  else
  begin
    // Weitergabe als Argument: Was die Routine damit macht, weiß nur der Index.
    AUse := NewUse(TObjectUseKind.Argument, ACall, TSyntaxNodes.IndexOf(ACall, ACurrent) - 1);
  end;
end;

{ TObjectUses }

class function TObjectUses.IsTypeCast(ACall: TSyntaxNode): Boolean;
var
  mName: string;
begin
  Result := (ACall.ChildCount = 2) and (ACall[0].Kind = TSyntaxKind.Identifier);
  if Result then
  begin
    mName := ACall[0].Name;
    Result := LooksLikeType(mName) or TTextNames.LooksLikeInterface(mName) or SameText(mName, 'Pointer');
  end;
end;

class function TObjectUses.Classify(ANode: TSyntaxNode): TObjectUse;
var
  mCurrent, mParent: TSyntaxNode;
  mDone: Boolean;
begin
  Result := NewUse(TObjectUseKind.Use, nil, -1);
  mCurrent := ANode;
  mDone := False;
  while not mDone and (mCurrent.Parent <> nil) do
  begin
    mParent := mCurrent.Parent;
    mDone := True;
    case mParent.Kind of
      TSyntaxKind.MemberAccess:
        Result.Kind := UseInMember(mParent);
      TSyntaxKind.Call:
        mDone := UseInCall(mParent, mCurrent, Result);
      TSyntaxKind.ParenExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.IfExpr:
        mDone := False;
      TSyntaxKind.BinaryExpr:
        if SameText(mParent.Name, 'as') then
        begin
          Result.Kind := TObjectUseKind.Escape;
        end;
      TSyntaxKind.AssignStatement:
        if mParent[0] = mCurrent then
        begin
          Result := NewUse(TObjectUseKind.Assigned, mParent, -1);
        end
        else
        begin
          // Rechts von :=: Das Objekt hat danach einen zweiten Verweis.
          Result.Kind := TObjectUseKind.Escape;
        end;
      TSyntaxKind.AddressOf, TSyntaxKind.SetConstructor, TSyntaxKind.RaiseStatement, TSyntaxKind.WithStatement,
      TSyntaxKind.ForInStatement, TSyntaxKind.InlineVar, TSyntaxKind.VarDecl, TSyntaxKind.AnonymousMethod:
        Result.Kind := TObjectUseKind.Escape;
    else
      Result.Kind := TObjectUseKind.Use;
    end;
    mCurrent := mParent;
  end;
end;

end.
