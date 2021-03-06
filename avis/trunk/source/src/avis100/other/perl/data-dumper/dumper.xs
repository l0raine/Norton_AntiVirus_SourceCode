#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#ifdef __cplusplus
}
#endif

static SV	*freezer;
static SV	*toaster;

static I32 num_q _((char *s));
static I32 esc_q _((char *dest, char *src, STRLEN slen));
static SV *sv_x _((SV *sv, char *str, STRLEN len, I32 n));
static I32 DD_dump _((SV *val, char *name, STRLEN namelen, SV *retval,
		      HV *seenhv, AV *postav, I32 *levelp, I32 indent,
		      SV *pad, SV *xpad, SV *apad, SV *sep,
		      SV *freezer, SV *toaster,
		      I32 purity, I32 deepcopy, I32 quotekeys));

/* does a string need to be protected? */
static I32
needs_quote(s)
    register char *s;
{
TOP:
    if (s[0] == ':') {
	if (*++s) {
	    if (*s++ != ':')
		return 1;
	}
	else
	    return 1;
    }
    if (isIDFIRST(*s)) {
	while (*++s)
	    if (!isALNUM(*s))
		if (*s == ':')
		    goto TOP;
		else
		    return 1;
    }
    else 
	return 1;
    return 0;
}

/* count the number of "'"s and "\"s in string */
static I32
num_q(s)
    register char *s;
{
    register I32 ret = 0;
    
    while (*s) {
	if (*s == '\'' || *s == '\\')
	    ++ret;
	++s;
    }
    return ret;
}


/* returns number of chars added to escape "'"s and "\"s in s */
/* slen number of characters in s will be escaped */
/* destination must be long enough for additional chars */
static I32
esc_q(d, s, slen)
    register char *d;
register char *s;
register STRLEN slen;
{
    register I32 ret = 0;
    
    while (slen > 0) {
	switch (*s) {
	case '\'':
	case '\\':
	    *d = '\\';
	    ++d; ++ret;
	default:
	    *d = *s;
	    ++d; ++s; --slen;
	    break;
	}
    }
    return ret;
}

/* append a repeated string to an SV */
static SV *
sv_x(sv, str, len, n)
register SV *sv;
register char *str;
register STRLEN len;
I32 n;
{
    if (sv == Nullsv)
	sv = newSVpv("", 0);
    else
	assert(SvTYPE(sv) >= SVt_PV);

    if (n > 0) {
	SvGROW(sv, len*n + SvCUR(sv) + 1);
	if (len == 1) {
	    char *start = SvPVX(sv) + SvCUR(sv);
	    SvCUR(sv) += n;
	    start[n] = '\0';
	    while (n > 0)
		start[--n] = str[0];
	}
	else
	    while (n > 0) {
		sv_catpvn(sv, str, len);
		--n;
	    }
    }
    return sv;
}

/*
 * This ought to be split into smaller functions. (it is one long function since
 * it exactly parallels the perl version, which was one long thing for
 * efficiency raisins.)  Ugggh!
 */
static I32
DD_dump(val, name, namelen, retval, seenhv, postav, levelp, indent, pad, xpad,
	apad, sep, freezer, toaster, purity, deepcopy, quotekeys)
SV	*val;
char	*name;
STRLEN	namelen;
SV	*retval;
HV	*seenhv;
AV	*postav;
I32	*levelp;
I32	indent;
SV	*pad;
SV	*xpad;
SV	*apad;
SV	*sep;
SV	*freezer;
SV	*toaster;
I32	purity;
I32	deepcopy;
I32	quotekeys;
{
    char tmpbuf[128];
    U32 i;
    char *c, *r, *realpack, id[128];
    SV **svp;
    SV *sv;
    SV *blesspad = Nullsv;
    SV *ipad;
    SV *ival;
    AV *seenentry;
    char *iname;
    STRLEN inamelen, idlen = 0;
    U32 flags;
    U32 realtype;

    if (!val)
	return 0;

    flags = SvFLAGS(val);
    realtype = SvTYPE(val);
    
    if (SvGMAGICAL(val))
        mg_get(val);
    if (val == &sv_undef || !SvOK(val)) {
	sv_catpvn(retval, "undef", 5);
	return 1;
    }
    if (SvROK(val)) {

	if (SvOBJECT(SvRV(val)) && freezer &&
	    SvPOK(freezer) && SvCUR(freezer))
	{
	    dSP; ENTER; SAVETMPS; PUSHMARK(sp);
	    XPUSHs(val); PUTBACK;
	    i = perl_call_method(SvPVX(freezer), G_EVAL|G_SCALAR);
	    SPAGAIN;
	    if (SvTRUE(GvSV(errgv)))
		warn("WARNING(Freezer method call failed): %s",
		     SvPVX(GvSV(errgv)));
	    else if (i)
		val = newSVsv(POPs);
	    PUTBACK; FREETMPS; LEAVE;
	    if (i)
		(void)sv_2mortal(val);
	}
	
	ival = SvRV(val);
	flags = SvFLAGS(ival);
	realtype = SvTYPE(ival);
        (void) sprintf(id, "0x%lx", (unsigned long)ival);
	idlen = strlen(id);
	if (SvOBJECT(ival))
	    realpack = HvNAME(SvSTASH(ival));
	else
	    realpack = Nullch;
	if ((svp = hv_fetch(seenhv, id, idlen, FALSE)) &&
	    (sv = *svp) && SvROK(sv) &&
	    (seenentry = (AV*)SvRV(sv))) {
	    SV *othername;
	    if ((svp = av_fetch(seenentry, 0, FALSE)) && (othername = *svp)) {
		if (purity && *levelp > 0) {
		    SV *postentry;
		    
		    if (realtype == SVt_PVHV)
			sv_catpvn(retval, "{}", 2);
		    else if (realtype == SVt_PVAV)
			sv_catpvn(retval, "[]", 2);
		    else
			sv_catpvn(retval, "''", 2);
		    postentry = newSVpv(name, namelen);
		    sv_catpvn(postentry, " = ", 3);
		    sv_catsv(postentry, othername);
		    av_push(postav, postentry);
		}
		else {
		    if (name[0] == '@' || name[0] == '%') {
			if ((SvPVX(othername))[0] == '\\' &&
			    (SvPVX(othername))[1] == name[0]) {
			    sv_catpvn(retval, SvPVX(othername)+1, SvCUR(othername)-1);
			}
			else {
			    sv_catpvn(retval, name, 1);
			    sv_catpvn(retval, "{", 1);
			    sv_catsv(retval, othername);
			    sv_catpvn(retval, "}", 1);
			}
		    }
		    else
			sv_catsv(retval, othername);
		}
		return 1;
	    }
	    else {
		warn("ref name not found for %s", id);
		return 0;
	    }
	}
	else {   /* store our name and continue */
	    SV *namesv;
	    if (name[0] == '@' || name[0] == '%') {
		namesv = newSVpv("\\", 1);
		sv_catpvn(namesv, name, namelen);
	    }
	    else if (realtype == SVt_PVCV && name[0] == '*') {
		namesv = newSVpv("\\", 2);
		sv_catpvn(namesv, name, namelen);
		(SvPVX(namesv))[1] = '&';
	    }
	    else
		namesv = newSVpv(name, namelen);
	    seenentry = newAV();
	    av_push(seenentry, namesv);
	    (void)SvREFCNT_inc(val);
	    av_push(seenentry, val);
	    (void)hv_store(seenhv, id, strlen(id), newRV((SV*)seenentry), 0);
	    SvREFCNT_dec(seenentry);
	}
	
	(*levelp)++;
	ipad = sv_x(Nullsv, SvPVX(xpad), SvCUR(xpad), *levelp);

	if (realpack) {   /* we have a blessed ref */
	    sv_catpvn(retval, "bless( ", 7);
	    if (indent >= 2) {
		blesspad = apad;
		apad = newSVsv(apad);
		sv_catpvn(apad, "       ", 7);
	    }
	}

	if (realtype <= SVt_PVBM || realtype == SVt_PVGV) {  /* scalars */
	    if (realpack && realtype != SVt_PVGV) {          /* blessed */ 
		sv_catpvn(retval, "do{\\(my $o = ", 13);
		DD_dump(ival, "", 0, retval, seenhv, postav,
			levelp,	indent, pad, xpad, apad, sep,
			freezer, toaster, purity, deepcopy, quotekeys);
		sv_catpvn(retval, ")}", 2);
	    }
	    else {
		sv_catpvn(retval, "\\", 1);
		DD_dump(ival, "", 0, retval, seenhv, postav,
			levelp,	indent, pad, xpad, apad, sep,
			freezer, toaster, purity, deepcopy, quotekeys);
	    }
	}
	else if (realtype == SVt_PVAV) {
	    SV *totpad;
	    I32 ix = 0;
	    I32 ixmax = av_len((AV *)ival);
	    
	    SV *ixsv = newSViv(0);
	    /* allowing for a 24 char wide array index */
	    iname = New(0, iname, namelen+28, char);
	    (void)strcpy(iname, name);
	    inamelen = namelen;
	    if (name[0] == '@') {
		sv_catpvn(retval, "(", 1);
		iname[0] = '$';
	    }
	    else {
		sv_catpvn(retval, "[", 1);
		if (namelen > 0 && name[namelen-1] != ']' && name[namelen-1] != '}') {
		    iname[inamelen++] = '-'; iname[inamelen++] = '>';
		    iname[inamelen] = '\0';
		}
	    }
	    if (iname[0] == '*' && iname[inamelen-1] == '}' && inamelen >= 8 &&
		(instr(iname+inamelen-8, "{SCALAR}") ||
		 instr(iname+inamelen-7, "{ARRAY}") ||
		 instr(iname+inamelen-6, "{HASH}"))) {
		iname[inamelen++] = '-'; iname[inamelen++] = '>';
	    }
	    iname[inamelen++] = '['; iname[inamelen] = '\0';
	    totpad = newSVsv(sep);
	    sv_catsv(totpad, pad);
	    sv_catsv(totpad, apad);

	    for (ix = 0; ix <= ixmax; ++ix) {
		STRLEN ilen;
		SV *elem;
		svp = av_fetch((AV*)ival, ix, FALSE);
		if (svp)
		    elem = *svp;
		else
		    elem = &sv_undef;
		
		ilen = inamelen;
		sv_setiv(ixsv, ix);
                (void) sprintf(iname+ilen, "%ld", ix);
		ilen = strlen(iname);
		iname[ilen++] = ']'; iname[ilen] = '\0';
		if (indent >= 3) {
		    sv_catsv(retval, totpad);
		    sv_catsv(retval, ipad);
		    sv_catpvn(retval, "#", 1);
		    sv_catsv(retval, ixsv);
		}
		sv_catsv(retval, totpad);
		sv_catsv(retval, ipad);
		DD_dump(elem, iname, ilen, retval, seenhv, postav,
			levelp,	indent, pad, xpad, apad, sep,
			freezer, toaster, purity, deepcopy, quotekeys);
		if (ix < ixmax)
		    sv_catpvn(retval, ",", 1);
	    }
	    if (ixmax >= 0) {
		SV *opad = sv_x(Nullsv, SvPVX(xpad), SvCUR(xpad), (*levelp)-1);
		sv_catsv(retval, totpad);
		sv_catsv(retval, opad);
		SvREFCNT_dec(opad);
	    }
	    if (name[0] == '@')
		sv_catpvn(retval, ")", 1);
	    else
		sv_catpvn(retval, "]", 1);
	    SvREFCNT_dec(ixsv);
	    SvREFCNT_dec(totpad);
	    Safefree(iname);
	}
	else if (realtype == SVt_PVHV) {
	    SV *totpad, *newapad;
	    SV *iname, *sname;
	    HE *entry;
	    char *key;
	    I32 klen;
	    SV *hval;
	    
	    iname = newSVpv(name, namelen);
	    if (name[0] == '%') {
		sv_catpvn(retval, "(", 1);
		(SvPVX(iname))[0] = '$';
	    }
	    else {
		sv_catpvn(retval, "{", 1);
		if (namelen > 0 && name[namelen-1] != ']' && name[namelen-1] != '}') {
		    sv_catpvn(iname, "->", 2);
		}
	    }
	    if (name[0] == '*' && name[namelen-1] == '}' && namelen >= 8 &&
		(instr(name+namelen-8, "{SCALAR}") ||
		 instr(name+namelen-7, "{ARRAY}") ||
		 instr(name+namelen-6, "{HASH}"))) {
		sv_catpvn(iname, "->", 2);
	    }
	    sv_catpvn(iname, "{", 1);
	    totpad = newSVsv(sep);
	    sv_catsv(totpad, pad);
	    sv_catsv(totpad, apad);
	    
	    (void)hv_iterinit((HV*)ival);
	    i = 0;
	    while ((entry = hv_iternext((HV*)ival)))  {
		char *nkey;
		I32 nticks = 0;
		
		if (i)
		    sv_catpvn(retval, ",", 1);
		i++;
		key = hv_iterkey(entry, &klen);
		hval = hv_iterval((HV*)ival, entry);

		if (quotekeys || needs_quote(key)) {
		    nticks = num_q(key);
		    New(0, nkey, klen+nticks+3, char);
		    nkey[0] = '\'';
		    if (nticks)
			klen += esc_q(nkey+1, key, klen);
		    else
			(void)Copy(key, nkey+1, klen, char);
		    nkey[++klen] = '\'';
		    nkey[++klen] = '\0';
		}
		else {
		    New(0, nkey, klen, char);
		    (void)Copy(key, nkey, klen, char);
		}
		
		sname = newSVsv(iname);
		sv_catpvn(sname, nkey, klen);
		sv_catpvn(sname, "}", 1);

		sv_catsv(retval, totpad);
		sv_catsv(retval, ipad);
		sv_catpvn(retval, nkey, klen);
		sv_catpvn(retval, " => ", 4);
		if (indent >= 2) {
		    char *extra;
		    I32 elen = 0;
		    newapad = newSVsv(apad);
		    New(0, extra, klen+4+1, char);
		    while (elen < (klen+4))
			extra[elen++] = ' ';
		    extra[elen] = '\0';
		    sv_catpvn(newapad, extra, elen);
		    Safefree(extra);
		}
		else
		    newapad = apad;

		DD_dump(hval, SvPVX(sname), SvCUR(sname), retval, seenhv,
			postav, levelp,	indent, pad, xpad, newapad, sep,
			freezer, toaster, purity, deepcopy, quotekeys);
		SvREFCNT_dec(sname);
		Safefree(nkey);
		if (indent >= 2)
		    SvREFCNT_dec(newapad);
	    }
	    if (i) {
		SV *opad = sv_x(Nullsv, SvPVX(xpad), SvCUR(xpad), *levelp-1);
		sv_catsv(retval, totpad);
		sv_catsv(retval, opad);
		SvREFCNT_dec(opad);
	    }
	    if (name[0] == '%')
		sv_catpvn(retval, ")", 1);
	    else
		sv_catpvn(retval, "}", 1);
	    SvREFCNT_dec(iname);
	    SvREFCNT_dec(totpad);
	}
	else if (realtype == SVt_PVCV) {
	    sv_catpvn(retval, "sub { \"DUMMY\" }", 15);
	    if (purity)
		warn("Encountered CODE ref, using dummy placeholder");
	}
	else {
	    warn("cannot handle ref type %ld", realtype);
	}

	if (realpack) {  /* free blessed allocs */
	    if (indent >= 2) {
		SvREFCNT_dec(apad);
		apad = blesspad;
	    }
	    sv_catpvn(retval, ", '", 3);
	    sv_catpvn(retval, realpack, strlen(realpack));
	    sv_catpvn(retval, "' )", 3);
	    if (toaster && SvPOK(toaster) && SvCUR(toaster)) {
		sv_catpvn(retval, "->", 2);
		sv_catsv(retval, toaster);
		sv_catpvn(retval, "()", 2);
	    }
	}
	SvREFCNT_dec(ipad);
	(*levelp)--;
    }
    else {
	STRLEN i;
	
	if (namelen) {
	    (void) sprintf(id, "0x%lx", (unsigned long)val);
	    if ((svp = hv_fetch(seenhv, id, (idlen = strlen(id)), FALSE)) &&
		(sv = *svp) && SvROK(sv) &&
		(seenentry = (AV*)SvRV(sv))) {
		SV *othername;
		if ((svp = av_fetch(seenentry, 0, FALSE)) && (othername = *svp)) {
		    sv_catsv(retval, othername);
		    return 1;
		}
	    }
	    else {
		SV *namesv;
		namesv = newSVpv("\\", 1);
		sv_catpvn(namesv, name, namelen);
		seenentry = newAV();
		av_push(seenentry, namesv);
		(void)SvREFCNT_inc(val);
		av_push(seenentry, val);
		(void)hv_store(seenhv, id, strlen(id), newRV((SV*)seenentry), 0);
		SvREFCNT_dec(seenentry);
	    }
	}
	
	if (SvIOK(val)) {
            STRLEN len;
	    i = SvIV(val);
            (void) sprintf(tmpbuf, "%d", i);
            len = strlen(tmpbuf);
	    sv_catpvn(retval, tmpbuf, len);
	    return 1;
	}
	else if (realtype == SVt_PVGV) {/* GLOBs can end up with scribbly names */
	    c = SvPV(val, i);
	    ++c; --i;			/* just get the name */
	    if (i >= 6 && strncmp(c, "main::", 6) == 0) {
		c += 4;
		i -= 4;
	    }
	    if (needs_quote(c)) {
		sv_grow(retval, SvCUR(retval)+6+2*i);
		r = SvPVX(retval)+SvCUR(retval);
		r[0] = '*'; r[1] = '{';	r[2] = '\'';
		i += esc_q(r+3, c, i);
		i += 3;
		r[i++] = '\''; r[i++] = '}';
		r[i] = '\0';
	    }
	    else {
		sv_grow(retval, SvCUR(retval)+i+2);
		r = SvPVX(retval)+SvCUR(retval);
		r[0] = '*'; strcpy(r+1, c);
		i++;
	    }

	    if (purity) {
		static char *entries[] = { "{SCALAR}", "{ARRAY}", "{HASH}" };
		static STRLEN sizes[] = { 8, 7, 6 };
		SV *e;
		SV *nname = newSVpv("", 0);
		SV *newapad = newSVpv("", 0);
		GV *gv = (GV*)val;
		I32 j;
		
		for (j=0; j<3; j++) {
		    e = ((j == 0) ? GvSV(gv) : (j == 1) ? (SV*)GvAV(gv) : (SV*)GvHV(gv));
		    if (e) {
			I32 nlevel = 0;
			SV *postentry = newSVpv(r,i);
			
			sv_setsv(nname, postentry);
			sv_catpvn(nname, entries[j], sizes[j]);
			sv_catpvn(postentry, " = ", 3);
			av_push(postav, postentry);
			e = newRV(e);
			
			SvCUR(newapad) = 0;
			if (indent >= 2)
			    (void)sv_x(newapad, " ", 1, SvCUR(postentry));
			
			DD_dump(e, SvPVX(nname), SvCUR(nname), postentry,
				seenhv, postav, &nlevel, indent, pad, xpad,
				newapad, sep, freezer, toaster, purity,
				deepcopy, quotekeys);
			SvREFCNT_dec(e);
		    }
		}
		
		SvREFCNT_dec(newapad);
		SvREFCNT_dec(nname);
	    }
	}
	else {
	    c = SvPV(val, i);
	    sv_grow(retval, SvCUR(retval)+3+2*i);
	    r = SvPVX(retval)+SvCUR(retval);
	    r[0] = '\'';
	    i += esc_q(r+1, c, i);
	    ++i;
	    r[i++] = '\'';
	    r[i] = '\0';
	}
	SvCUR_set(retval, SvCUR(retval)+i);
    }

    if (deepcopy && idlen)
	(void)hv_delete(seenhv, id, idlen, G_DISCARD);
	
    return 1;
}


MODULE = Data::Dumper		PACKAGE = Data::Dumper         PREFIX = Data_Dumper_

#
# This is the exact equivalent of Dump.  Well, almost. The things that are
# different as of now (due to Laziness):
#   * doesnt do double-quotes yet.
#

void
Data_Dumper_Dumpxs(href, ...)
	SV	*href;
	PROTOTYPE: $;$$
	PPCODE:
	{
	    HV *hv;
	    SV *retval, *valstr;
	    HV *seenhv = Nullhv;
	    AV *postav, *todumpav, *namesav;
	    I32 level = 0;
	    I32 indent, terse, useqq, i, imax, postlen;
	    SV **svp;
	    SV *val, *name, *pad, *xpad, *apad, *sep, *tmp, *varname;
	    SV *freezer, *toaster;
	    I32 purity, deepcopy, quotekeys;
	    char tmpbuf[1024];
	    I32 gimme = GIMME;

	    if (!SvROK(href)) {		/* call new to get an object first */
		SV *valarray;
		SV *namearray;

		if (items == 3) {
		    valarray = ST(1);
		    namearray = ST(2);
		}
		else
		    croak("Usage: Data::Dumper::Dumpxs(PACKAGE, VAL_ARY_REF, NAME_ARY_REF)");
		
		ENTER;
		SAVETMPS;
		
		PUSHMARK(sp);
		XPUSHs(href);
		XPUSHs(sv_2mortal(newSVsv(valarray)));
		XPUSHs(sv_2mortal(newSVsv(namearray)));
		PUTBACK;
		i = perl_call_method("new", G_SCALAR);
		SPAGAIN;
		if (i)
		    href = newSVsv(POPs);

		PUTBACK;
		FREETMPS;
		LEAVE;
		if (i)
		    (void)sv_2mortal(href);
	    }

	    todumpav = namesav = Nullav;
	    seenhv = Nullhv;
	    val = pad = xpad = apad = sep = tmp = varname
		= freezer = toaster = &sv_undef;
	    name = sv_newmortal();
	    indent = 2;
	    terse = useqq = purity = deepcopy = 0;
	    quotekeys = 1;
	    
	    retval = newSVpv("", 0);
	    if (SvROK(href)
		&& (hv = (HV*)SvRV((SV*)href))
		&& SvTYPE(hv) == SVt_PVHV)		{

		if ((svp = hv_fetch(hv, "seen", 4, FALSE)) && SvROK(*svp))
		    seenhv = (HV*)SvRV(*svp);
		if ((svp = hv_fetch(hv, "todump", 6, FALSE)) && SvROK(*svp))
		    todumpav = (AV*)SvRV(*svp);
		if ((svp = hv_fetch(hv, "names", 5, FALSE)) && SvROK(*svp))
		    namesav = (AV*)SvRV(*svp);
		if ((svp = hv_fetch(hv, "indent", 6, FALSE)))
		    indent = SvIV(*svp);
		if ((svp = hv_fetch(hv, "purity", 6, FALSE)))
		    purity = SvIV(*svp);
		if ((svp = hv_fetch(hv, "terse", 5, FALSE)))
		    terse = SvTRUE(*svp);
		if ((svp = hv_fetch(hv, "useqq", 5, FALSE)))
		    useqq = SvTRUE(*svp);
		if ((svp = hv_fetch(hv, "pad", 3, FALSE)))
		    pad = *svp;
		if ((svp = hv_fetch(hv, "xpad", 4, FALSE)))
		    xpad = *svp;
		if ((svp = hv_fetch(hv, "apad", 4, FALSE)))
		    apad = *svp;
		if ((svp = hv_fetch(hv, "sep", 3, FALSE)))
		    sep = *svp;
		if ((svp = hv_fetch(hv, "varname", 7, FALSE)))
		    varname = *svp;
		if ((svp = hv_fetch(hv, "freezer", 7, FALSE)))
		    freezer = *svp;
		if ((svp = hv_fetch(hv, "toaster", 7, FALSE)))
		    toaster = *svp;
		if ((svp = hv_fetch(hv, "deepcopy", 8, FALSE)))
		    deepcopy = SvTRUE(*svp);
		if ((svp = hv_fetch(hv, "quotekeys", 9, FALSE)))
		    quotekeys = SvTRUE(*svp);
		postav = newAV();

		if (todumpav)
		    imax = av_len(todumpav);
		else
		    imax = -1;
		valstr = newSVpv("",0);
		for (i = 0; i <= imax; ++i) {
		    SV *newapad;
		    
		    av_clear(postav);
		    if ((svp = av_fetch(todumpav, i, FALSE)))
			val = *svp;
		    else
			val = &sv_undef;
		    if ((svp = av_fetch(namesav, i, TRUE)))
			sv_setsv(name, *svp);
		    else
			SvOK_off(name);
		    
		    if (SvOK(name)) {
			if ((SvPVX(name))[0] == '*') {
			    if (SvROK(val)) {
				switch (SvTYPE(SvRV(val))) {
				case SVt_PVAV:
				    (SvPVX(name))[0] = '@';
				    break;
				case SVt_PVHV:
				    (SvPVX(name))[0] = '%';
				    break;
				case SVt_PVCV:
				    (SvPVX(name))[0] = '*';
				    break;
				default:
				    (SvPVX(name))[0] = '$';
				    break;
				}
			    }
			    else
				(SvPVX(name))[0] = '$';
			}
			else if ((SvPVX(name))[0] != '$')
			    sv_insert(name, 0, 0, "$", 1);
		    }
		    else {
			STRLEN nchars = 0;
			sv_setpvn(name, "$", 1);
			sv_catsv(name, varname);
			(void) sprintf(tmpbuf, "%ld", i+1);
			nchars = strlen(tmpbuf);
			sv_catpvn(name, tmpbuf, nchars);
		    }
		    
		    if (indent >= 2) {
			SV *tmpsv = sv_x(Nullsv, " ", 1, SvCUR(name)+3);
			newapad = newSVsv(apad);
			sv_catsv(newapad, tmpsv);
			SvREFCNT_dec(tmpsv);
		    }
		    else
			newapad = apad;
		    
		    DD_dump(val, SvPVX(name), SvCUR(name), valstr, seenhv,
			    postav, &level, indent, pad, xpad, newapad, sep,
			    freezer, toaster, purity, deepcopy, quotekeys);
		    
		    if (indent >= 2)
			SvREFCNT_dec(newapad);

		    postlen = av_len(postav);
		    if (postlen >= 0 || !terse) {
			sv_insert(valstr, 0, 0, " = ", 3);
			sv_insert(valstr, 0, 0, SvPVX(name), SvCUR(name));
			sv_catpvn(valstr, ";", 1);
		    }
		    sv_catsv(retval, pad);
		    sv_catsv(retval, valstr);
		    sv_catsv(retval, sep);
		    if (postlen >= 0) {
			I32 i;
			sv_catsv(retval, pad);
			for (i = 0; i <= postlen; ++i) {
			    SV *elem;
			    svp = av_fetch(postav, i, FALSE);
			    if (svp && (elem = *svp)) {
				sv_catsv(retval, elem);
				if (i < postlen) {
				    sv_catpvn(retval, ";", 1);
				    sv_catsv(retval, sep);
				    sv_catsv(retval, pad);
				}
			    }
			}
			sv_catpvn(retval, ";", 1);
			    sv_catsv(retval, sep);
		    }
		    sv_setpvn(valstr, "", 0);
		    if (gimme == G_ARRAY) {
			XPUSHs(sv_2mortal(retval));
			if (i < imax)	/* not the last time thro ? */
			    retval = newSVpv("",0);
		    }
		}
		SvREFCNT_dec(postav);
		SvREFCNT_dec(valstr);
	    }
	    else
		croak("Call to new() method failed to return HASH ref");
	    if (gimme == G_SCALAR)
		XPUSHs(sv_2mortal(retval));
	}
