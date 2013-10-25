{- |
Module      :  Data.PDRS.LambdaCalculus
Copyright   :  (c) Harm Brouwer and Noortje Venhuizen
License     :  Apache-2.0

Maintainer  :  me@hbrouwer.eu, n.j.venhuizen@rug.nl
Stability   :  provisional
Portability :  portable

PDRS lambda calculus; alpha conversion, beta reduction,
function composition, and `PDRS purification'
-}

module Data.PDRS.LambdaCalculus
(
  pdrsAlphaConvert
, pdrsBetaReduce
, (<<@>>)
, pdrsFunctionCompose
, (<<.>>)
, pdrsPurify
) where

import Data.DRS.LambdaCalculus (renameVar)
import Data.PDRS.Structure
import Data.PDRS.Variables

import Data.List (delete, intersect, nub, partition, union)

---------------------------------------------------------------------------
-- * Exported
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- ** Alpha Conversion
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- | Applies alpha conversion to a 'PDRS' on the basis of conversion lists
-- for 'PVar's and 'PDRSRef's.
---------------------------------------------------------------------------
pdrsAlphaConvert :: PDRS -> [(PVar,PVar)] -> [(PDRSRef,PDRSRef)] -> PDRS
pdrsAlphaConvert p = renameSubPDRS p p

---------------------------------------------------------------------------
-- ** Beta Reduction
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- | Apply beta reduction on an 'AbstractPDRS' with a 'PDRSAtom'.
---------------------------------------------------------------------------
pdrsBetaReduce :: (AbstractPDRS a, PDRSAtom b) => (b -> a) -> b -> a
pdrsBetaReduce a = a

-- | Infix notation for 'pdrsBetaReduce'.
(<<@>>) :: (AbstractPDRS a, PDRSAtom b) => (b -> a) -> b -> a
up <<@>> ap = up `pdrsBetaReduce` ap

---------------------------------------------------------------------------
-- ** Function Composition
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- | Apply function composition to two 'unresolved PDRS's, yielding
-- a new 'unresolved PDRS'.
---------------------------------------------------------------------------
pdrsFunctionCompose :: (b -> c) -> (a -> b) -> a -> c
pdrsFunctionCompose = (.)

-- | Infix notation for 'pdrsFunctionCompose'.
(<<.>>) :: (b -> c) -> (a -> b) -> a -> c
a1 <<.>> a2 = a1 `pdrsFunctionCompose` a2

---------------------------------------------------------------------------
-- ** PDRS Purification
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- | Converts a 'PDRS' into a /pure/ 'PDRS' by first purifying its
-- projection variables, and then purifying its projected referents, where:
--
-- [A 'PDRS' is pure /iff/:]
--
-- * There are no occurrences of duplicate, unbound uses of the same
--   variable ('PVar' or 'PDRSRef').
---------------------------------------------------------------------------
pdrsPurify :: PDRS -> PDRS
pdrsPurify gp = purifyPRefs cgp cgp (zip prs (newPRefs prs (pdrsVariables cgp)))
  where cgp = fst $ purifyPVars (gp,pdrsFreePVars gp gp) gp
        prs = snd $ unboundDupPRefs cgp cgp []

---------------------------------------------------------------------------
-- * Private
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- ** Type classes
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- | Type class for a 'PDRSAtom', which is either a 'PDRS' or a 'PDRSRef'.
---------------------------------------------------------------------------
class PDRSAtom a
instance PDRSAtom PDRS
instance PDRSAtom PDRSRef

---------------------------------------------------------------------------
-- | Type class for an 'AbstractPDRS', which is either a resolved 'PDRS',
-- or an unresolved 'PDRS' that takes a 'PDRSAtom' and yields an 
-- 'AbstractPDRS'.
---------------------------------------------------------------------------
class AbstractPDRS a
instance AbstractPDRS PDRS
instance (PDRSAtom a, AbstractPDRS b) => AbstractPDRS (a -> b)

---------------------------------------------------------------------------
-- ** PDRS renaming
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- | Applies alpha conversion to a 'PDRS' @sp@, which is a sub-'PDRS' of
-- the global 'PDRS' @gp@, on the basis of conversion lists for 'PVar's
-- @ps@ and 'PDRSRef's @rs@.
---------------------------------------------------------------------------
renameSubPDRS :: PDRS -> PDRS -> [(PVar,PVar)] -> [(PDRSRef,PDRSRef)] -> PDRS
renameSubPDRS lp@(LambdaPDRS _) _ _ _    = lp
renameSubPDRS (AMerge p1 p2) gp ps rs    = AMerge p1' p2'
  where p1' = renameSubPDRS p1 gp ps rs
        p2' = renameSubPDRS p2 gp ps rs
renameSubPDRS (PMerge p1 p2) gp ps rs    = PMerge p1' p2'
  where p1' = renameSubPDRS p1 gp ps rs
        p2' = renameSubPDRS p2 gp ps rs
renameSubPDRS lp@(PDRS l m u c) gp ps rs = PDRS l' m' u' c'
  where l' = renameVar l ps
        m' = renameMAPs m lp gp ps
        u' = renameUniverse u lp gp ps rs
        c' = renamePCons c lp gp ps rs

---------------------------------------------------------------------------
-- | Applies alpha conversion to a list of 'MAP's @m@, on the basis of a
-- conversion list for projection variables @ps@.
---------------------------------------------------------------------------
renameMAPs :: [MAP] -> PDRS -> PDRS -> [(PVar,PVar)] -> [MAP]
renameMAPs m lp gp ps = map (\(l1,l2) -> (renamePVar l1 lp gp ps, renamePVar l2 lp gp ps)) m

---------------------------------------------------------------------------
-- |  Applies alpha conversion to a list of 'PRef's @u@, on the basis of
-- a conversion list for 'PVar's @ps@ and 'PDRSRef's @rs@.
---------------------------------------------------------------------------
renameUniverse :: [PRef] -> PDRS -> PDRS -> [(PVar,PVar)] -> [(PDRSRef,PDRSRef)] -> [PRef]
renameUniverse u lp gp ps rs = map (\(PRef p r) -> PRef (renamePVar p lp gp ps) (renameVar r rs)) u

---------------------------------------------------------------------------
-- | Applies alpha conversion to a list of 'PCon's @c@ in
-- in local 'PDRS' @lp@ in global 'PDRS' @gp@, on the basis of
-- conversion lists for 'PVar's @ps@ and 'PDRSRef's @rs@.
---------------------------------------------------------------------------
renamePCons :: [PCon] -> PDRS -> PDRS -> [(PVar,PVar)] -> [(PDRSRef,PDRSRef)] -> [PCon]
renamePCons c lp gp ps rs = map rename c
  where rename :: PCon -> PCon
        rename (PCon p (Rel r d))    = PCon p' (Rel   r (map (flip (flip (flip (renamePDRSRef p') lp) gp) rs) d))
          where p' = renamePVar p lp gp ps
        rename (PCon p (Neg p1))     = PCon p' (Neg     (renameSubPDRS p1 gp ps rs))
          where p' = renamePVar p lp gp ps
        rename (PCon p (Imp p1 p2))  = PCon p' (Imp     (renameSubPDRS p1 gp ps rs)  (renameSubPDRS p2 gp ps rs))
          where p' = renamePVar p lp gp ps
        rename (PCon p (Or p1 p2))   = PCon p' (Or      (renameSubPDRS p1 gp ps rs)  (renameSubPDRS p2 gp ps rs))
          where p' = renamePVar p lp gp ps
        rename (PCon p (Prop r p1))  = PCon p' (Prop    (renamePDRSRef p' r lp gp rs)(renameSubPDRS p1 gp ps rs))
          where p' = renamePVar p lp gp ps
        rename (PCon p (Diamond p1)) = PCon p' (Diamond (renameSubPDRS p1 gp ps rs))
          where p' = renamePVar p lp gp ps
        rename (PCon p (Box  p1))    = PCon p' (Box     (renameSubPDRS p1 gp ps rs))
          where p' = renamePVar p lp gp ps

---------------------------------------------------------------------------
-- |  Applies alpha conversion to a list of projected referents @u@, in
--local 'PDRS' @lp@ in global 'PDRS' @gp@,on the basis of a conversion list
--for projection variables @ps@ and 'PDRS' referents @rs@
---------------------------------------------------------------------------
renamePDRSRef :: PVar -> PDRSRef -> PDRS -> PDRS -> [(PDRSRef,PDRSRef)] -> PDRSRef
renamePDRSRef pv r lp gp rs
  | pdrsBoundPRef (PRef pv r) lp gp = renameVar r rs
  | otherwise                       = r

---------------------------------------------------------------------------
-- | Converts a 'PVar' into a new 'PVar' in case it occurs bound in 
-- local 'PDRS' @lp@ in global 'PDRS' @gp@.
---------------------------------------------------------------------------
renamePVar :: PVar -> PDRS -> PDRS -> [(PVar,PVar)] -> PVar
renamePVar pv lp gp ps
  | pdrsBoundPVar pv lp gp = renameVar pv ps
  | otherwise              = pv

---------------------------------------------------------------------------
-- ** Purifying PVars
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- | Replaces duplicate uses of projection variables by new variables.
--
-- [This function implements the following algorithm:]
--
-- (1) start with the global 'PDRS' @gp@ and add all free 'PVar's in @gp@ to
-- the list of seen projection variables @pvs@ (see 'pdrsPurify');
-- 
-- 2. check the label @l@ of the first atomic 'PDRS' @lp@ against @pvs@
--    and, if necessary, alpha-convert @lp@ replacing @l@ for a new 'PVar';
-- 
-- 3. add the label and all 'PVar's from the universe and set of 'MAP's
--    of @pdrs@ to the list of seen projection variables @pvs@;
-- 
-- 4. go through all conditions of @pdrs@, while continually updating @pvs@.
---------------------------------------------------------------------------
purifyPVars :: (PDRS,[PVar]) -> PDRS -> (PDRS,[PVar])
purifyPVars (lp@(LambdaPDRS _),pvs) _  = (lp,pvs)
purifyPVars (AMerge p1 p2,pvs)      gp = (AMerge cp1 cp2,pvs2)
  where (cp1,pvs1) = purifyPVars (p1,pvs)  gp
        (cp2,pvs2) = purifyPVars (p2,pvs1) gp
purifyPVars (PMerge p1 p2,pvs)      gp = (PMerge cp1 cp2,pvs2)
  where (cp1,pvs1) = purifyPVars (p1,pvs)  gp
        (cp2,pvs2) = purifyPVars (p2,pvs1) gp
-- | Step 2.
-- In case we do not want to rename ambiguous bindings:
-- purifyPVars (lp@(PDRS l _ _ _),pvs) gp = (PDRS l1 m1 u1 c2,pvs1 `union` pvs2)
purifyPVars (lp@(PDRS l _ _ _),pvs) gp = (PDRS l1 m1 u1 c2,pvs2)
  where (PDRS l1 m1 u1 c1) = pdrsAlphaConvert lp (zip ol (newPVars ol (pdrsPVars gp `union` pvs))) []
        ol        = [l] `intersect` pvs
        (c2,pvs2) = purify (c1,pvs `union` pvs1)
        -- ^ In case we do not want to rename ambiguous bindings:
        -- (c2,pvs2) = purify (c1,pvs)
        -- | Step 3.
        pvs1      = l1:(concatMap (\(x,y) -> [x,y]) m1) `union` (map prefToPVar u1)
        -- | Step 4.
        purify :: ([PCon],[PVar]) -> ([PCon],[PVar])
        purify ([],pvs)                        = ([],pvs)
        purify (pc@(PCon p (Rel _ _)):pcs,pvs) = (pc:ccs,pvs1)
          where (ccs,pvs1) = purify (pcs,p:pvs)
        purify (PCon p (Neg p1):pcs,pvs)       = (PCon p (Neg cp1):ccs,pvs2)
          where (cp1,pvs1) = purifyPVars (p1,p:pvs) gp
                (ccs,pvs2) = purify (pcs,pvs1)
        purify (PCon p (Imp p1 p2):pcs,pvs)    = (PCon p (Imp cp1 cp2):ccs,pvs3)
          where (cp1,pvs1) = purifyPVars (renameSubPDRS p1 gp nps [],p:pvs) gp
                (cp2,pvs2) = purifyPVars (renameSubPDRS p2 gp nps [],pvs1) gp
                (ccs,pvs3) = purify (pcs,pvs2)
                nps  = zip ops (newPVars ops (pdrsPVars gp `union` pvs))
                ops  = p:pvs `intersect` [pdrsLabel p1]
                -- ^ In case we do not want to rename ambiguous bindings:
                -- ops = pdrsLabels p2 \\ p:pvs `intersect` [pdrsLabel p1]
        purify (PCon p (Or p1 p2):pcs,pvs)     = (PCon p (Or cp1 cp2):ccs,pvs3)
          where (cp1,pvs1) = purifyPVars (renameSubPDRS p1 gp nps [],p:pvs) gp
                (cp2,pvs2) = purifyPVars (renameSubPDRS p2 gp nps [],pvs1) gp
                (ccs,pvs3) = purify (pcs,pvs2)
                nps  = zip ops (newPVars ops (pdrsPVars gp `union` pvs))
                ops  = p:pvs `intersect` [pdrsLabel p1]
                -- ^ In case we do not want to rename ambiguous bindings:
                -- ops = pdrsLabels p2 \\ p:pvs `intersect` [pdrsLabel p1]
        purify (PCon p (Prop r p1):pcs,pvs)    = (PCon p (Prop r cp1):ccs,pvs2)
          where (cp1,pvs1) = purifyPVars (p1,p:pvs) gp
                (ccs,pvs2) = purify (pcs,pvs1)
        purify (PCon p (Diamond p1):pcs,pvs)   = (PCon p (Diamond cp1):ccs,pvs2)
          where (cp1,pvs1) = purifyPVars (p1,p:pvs) gp
                (ccs,pvs2) = purify (pcs,pvs1)
        purify (PCon p (Box p1):pcs,pvs)       = (PCon p (Box cp1):ccs,pvs2)
          where (cp1,pvs1) = purifyPVars (p1,p:pvs) gp
                (ccs,pvs2) = purify (pcs,pvs1)

---------------------------------------------------------------------------
-- ** Purifying PRefs
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- | Replaces duplicate uses of projection referents by new 'PRef's, where:
--
-- [Given conversion pair @(pr',npr)@, @pr@ is replaced by @npr@ /iff/]
--
-- * @pr@ equals @pr'@, or
--
-- * @pr@ and @pr'@ have the same referent and @pr@ is bound by
--   @pr'@ in global 'PDRS' @gp@, or
--
-- * @pr@ and @pr'@ have the same referent and both occur free
--   in subordinated contexts in @gp@.
---------------------------------------------------------------------------
purifyPRefs :: PDRS -> PDRS -> [(PRef,PRef)] -> PDRS
purifyPRefs lp@(LambdaPDRS _) _  _   = lp
purifyPRefs (AMerge p1 p2)    gp prs = AMerge (purifyPRefs p1 gp prs) (purifyPRefs p2 gp prs)
purifyPRefs (PMerge p1 p2)    gp prs = PMerge (purifyPRefs p1 gp prs) (purifyPRefs p2 gp prs)
purifyPRefs lp@(PDRS l m u c) gp prs = PDRS l m (map (convert prs) u) (map purify c)
  where -- | Converts a 'PRef' @pr@ based on a conversion list
        convert :: [(PRef,PRef)] -> PRef -> PRef
        convert [] pr                                    = pr
        convert  ((pr'@(PRef p' r'),npr):prs) pr@(PRef p r)
          | pr == pr'                                    = npr
          | r  == r' && pdrsPRefBoundByPRef pr lp pr' gp = npr
          | r  == r' && not(pdrsBoundPRef pr lp gp) 
            && (pdrsIsAccessibleContext p p' gp)         = npr
          | otherwise                                    = convert prs pr
        -- | A projected condition is /purify/ iff all its subordinated
        -- referents have been converted based on the conversion list.
        purify :: PCon -> PCon
        purify (PCon p (Rel r d))    = PCon p (Rel   r (map (purifyPDRSRef p) d))
        purify (PCon p (Neg p1))     = PCon p (Neg     (purifyPRefs p1 gp prs))
        purify (PCon p (Imp p1 p2))  = PCon p (Imp     (purifyPRefs p1 gp prs) (purifyPRefs p2 gp prs))
        purify (PCon p (Or  p1 p2))  = PCon p (Or      (purifyPRefs p1 gp prs) (purifyPRefs p2 gp prs))
        purify (PCon p (Prop r p1))  = PCon p (Prop    (purifyPDRSRef p r)     (purifyPRefs p1 gp prs))
        purify (PCon p (Diamond p1)) = PCon p (Diamond (purifyPRefs p1 gp prs))
        purify (PCon p (Box p1))     = PCon p (Box     (purifyPRefs p1 gp prs))
        purifyPDRSRef :: PVar -> PDRSRef -> PDRSRef
        purifyPDRSRef p r = prefToPDRSRef (convert prs (pdrsRefToPRef r p))

---------------------------------------------------------------------------
-- | Returns a tuple of existing 'PRef's @eps@ and unbound duplicate 'PRef's
-- @dps@ in a 'PDRS', based on a list of seen 'PRef's @prs@, where:
--
-- [@pr = ('PRef' p r)@ is duplicate in 'PDRS' @gp@ /iff/]
--
-- * There exists a @p'@, such that @pr' = ('PRef' p' r)@ is an element
--   of @prs@, and @pr@ and @pr'@ are /independent/.
---------------------------------------------------------------------------
unboundDupPRefs :: PDRS -> PDRS -> [PRef] -> ([PRef],[PRef])
unboundDupPRefs (LambdaPDRS _)    _  eps = (eps,[])
unboundDupPRefs (AMerge p1 p2)    gp eps = (eps2,dps1 ++ dps2)
  where (eps1,dps1) = unboundDupPRefs p1 gp eps
        (eps2,dps2) = unboundDupPRefs p2 gp eps1
unboundDupPRefs (PMerge p1 p2)    gp eps = (eps2,dps1 ++ dps2)
  where (eps1,dps1) = unboundDupPRefs p1 gp eps
        (eps2,dps2) = unboundDupPRefs p2 gp eps1
unboundDupPRefs lp@(PDRS _ _ u c) gp eps = (eps1,filter (`dup` eps) uu ++ dps1)
  where (eps1,dps1) = dups c (eps ++ uu)
        uu = unboundPRefs u
        -- | Returns whether 'PRef' @pr@ is /duplicate/ wrt a list of 'PRef's.
        dup :: PRef -> [PRef] -> Bool
        dup _ []                                       = False
        dup pr@(PRef _ r) (pr'@(PRef _ r'):prs)
          | r == r' && independentPRefs pr [pr'] lp gp = True
          | otherwise                                  = dup pr prs
        -- | Returns a tuple of existing 'PRef's @eps'@ and duplicate
        -- 'PRef's @dps'@, based on a list of 'PCon's and a list of existing
        -- 'PRef's @eps@. 
        dups :: [PCon] -> [PRef] -> ([PRef],[PRef])
        dups [] eps = (eps,[])
        dups (PCon p (Rel _ d):pcs)    eps = (eps2,dps1 ++ dps2)
          where (eps2,dps2) = dups pcs (eps ++ upd)
                upd  = unboundPRefs $ map (`pdrsRefToPRef` p) d
                dps1 = filter (\pd -> dup pd eps) upd
        dups (PCon p (Neg p1):pcs)     eps = (eps2,dps1 ++ dps2)
          where (eps1,dps1) = unboundDupPRefs p1 gp eps
                (eps2,dps2) = dups pcs eps1
        dups (PCon p (Imp p1 p2):pcs)  eps = (eps3,dps1 ++ dps2 ++ dps3)
          where (eps1,dps1) = unboundDupPRefs p1 gp eps
                (eps2,dps2) = unboundDupPRefs p2 gp eps1
                (eps3,dps3) = dups pcs eps2
        dups (PCon p (Or p1 p2):pcs)   eps = (eps3,dps1 ++ dps2 ++ dps3)
          where (eps1,dps1) = unboundDupPRefs p1 gp eps
                (eps2,dps2) = unboundDupPRefs p2 gp eps1
                (eps3,dps3) = dups pcs eps2
        dups (PCon p (Prop r p1):pcs)  eps = (eps3,dps1 ++ dps2 ++ dps3)
          where (eps1,dps1) = unboundDupPRefs p1 gp eps
                (eps2,dps2) = dups pcs eps1
                (eps3,dps3) = (eps2 ++ unboundPRefs [pr],filter (`dup` eps) [pr])
                pr          = pdrsRefToPRef r p
        dups (PCon p (Diamond p1):pcs) eps = (eps2,dps1 ++ dps2)
          where (eps1,dps1) = unboundDupPRefs p1 gp eps
                (eps2,dps2) = dups pcs eps1
        dups (PCon p (Box p1):pcs)     eps = (eps2,dps1 ++ dps2)
          where (eps1,dps1) = unboundDupPRefs p1 gp eps
                (eps2,dps2) = dups pcs eps1
        -- | Returns whether a referent is bound by some other referent
        -- than itself.
        unboundPRefs :: [PRef] -> [PRef]
        unboundPRefs prs = snd $ partition (\pr ->
          any (flip (pdrsPRefBoundByPRef pr lp) gp) (delete pr (pdrsUniverses gp))) prs

---------------------------------------------------------------------------
-- | Returns whether a 'PRef' @pr@ is /independent/ based on a list of
-- 'PRef's @prs@, where:
--
-- [@pr = ('PRef' p r)@ is independent w.r.t. @prs@ /iff/]
--
-- (1) @pr@ is not bound by any 'PRef' in @prs@; and
--
-- 2. it is not the case that @pr@ occurs free and there is some
--    element of @prs@ that is accessible from @pr@. (NB. this only
--    holds if both @pr@ and @pr'@ occur free in accessible contexts,
--    in which case they are not independent).
---------------------------------------------------------------------------
independentPRefs :: PRef -> [PRef] -> PDRS -> PDRS -> Bool
independentPRefs _ [] _ _                                          = True
independentPRefs pr@(PRef p r) prs lp gp
  | any (flip (pdrsPRefBoundByPRef pr lp) gp) prs                  = False
  | not(pdrsBoundPRef pr lp gp) 
    && any (\(PRef p' _) -> (pdrsIsAccessibleContext p p' gp)) prs = False
  | otherwise                                                      = True
