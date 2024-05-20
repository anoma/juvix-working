#[macro_use]
pub mod apply;
pub mod closure;
pub mod constr;
pub mod defs;
pub mod equality;
pub mod integer;
pub mod memory;

#[cfg(test)]
mod tests {
    use super::apply;
    use super::defs::*;
    use super::equality::*;
    use super::integer::*;
    use super::memory::*;

    fn program_fib(fid: Word, args: Vec<Word>) -> Word {
        const FUN_FIB: Word = 0;
        loop {
            match fid {
                FUN_FIB => {
                    #[allow(unused_mut)]
                    let mut tmp1: Word;
                    #[allow(unused_mut)]
                    let mut tmp2: Word;
                    if word_to_bool(smallint_le(args[0], make_smallint(1))) {
                        break args[0];
                    } else {
                        tmp1 = program_fib(FUN_FIB, vec![smallint_sub(args[0], make_smallint(1))]);
                        tmp2 = program_fib(FUN_FIB, vec![smallint_sub(args[0], make_smallint(2))]);
                        break (smallint_add(tmp1, tmp2));
                    }
                }
                _ => panic!("unknown function id"),
            }
        }
    }

    fn program_itfib(arg_fid: Word, mut args: Vec<Word>) -> Word {
        const FUN_ITFIB: Word = 0;
        const FUN_ITFIB_GO: Word = 1;
        #[allow(unused_mut)]
        let mut fid = arg_fid;
        loop {
            match fid {
                FUN_ITFIB => {
                    args[1] = 0;
                    args[2] = 1;
                    fid = FUN_ITFIB_GO;
                    continue;
                }
                FUN_ITFIB_GO => {
                    #[allow(unused_mut)]
                    let mut tmp1: Word;
                    if juvix_equal(args[0], make_smallint(0)) {
                        break args[1];
                    } else {
                        tmp1 = args[1];
                        args[1] = args[2];
                        args[2] = smallint_add(args[1], tmp1);
                        args[0] = smallint_sub(args[0], make_smallint(1));
                        fid = FUN_ITFIB_GO;
                        continue;
                    }
                }
                _ => panic!("unknown function id"),
            }
        }
    }

    fn program_closure_call(mem: &mut Memory, arg_fid: Word, mut args: Vec<Word>) -> Word {
        const FUN_MAIN: Word = 0;
        const FUN_CALCULATE: Word = 1;
        const FUN_APPLY_1: Word = 2;
        #[allow(unused_mut)]
        let mut fid = arg_fid;
        loop {
            match fid {
                FUN_MAIN => {
                    args[0] =
                        mem.alloc_closure(FUN_CALCULATE, &[make_smallint(5), make_smallint(3)], 1);
                    fid = FUN_APPLY_1;
                    continue;
                }
                FUN_CALCULATE => {
                    #[allow(unused_mut)]
                    let mut tmp1: Word;
                    tmp1 = smallint_mul(args[2], args[1]);
                    tmp1 = smallint_add(args[0], tmp1);
                    break tmp1;
                }
                FUN_APPLY_1 => {
                    (fid, args) = mem.call_closure(args[0], &[make_smallint(2)]);
                    continue;
                }
                _ => panic!("unknown function id"),
            }
        }
    }

    fn program_sk(mem: &mut Memory, arg_fid: Word, mut args: Vec<Word>) -> Word {
        const FUN_MAIN: Word = 0;
        const FUN_S: Word = 1;
        const FUN_K: Word = 2;
        const FUN_I: Word = 3;
        #[allow(unused_mut)]
        let mut fid = arg_fid;
        'program: loop {
            match fid {
                FUN_MAIN => {
                    let id = program_sk(mem, FUN_I, vec![]);
                    let x = apply!(
                        program_sk,
                        mem,
                        id,
                        vec![id, id, id, id, id, id, make_smallint(1)]
                    );
                    let y = apply!(
                        program_sk,
                        mem,
                        id,
                        vec![id, id, id, id, id, id, id, id, id, make_smallint(1)]
                    );
                    let z = apply!(
                        program_sk,
                        mem,
                        id,
                        vec![id, id, id, id, id, id, id, id, id, id, id, make_smallint(1)]
                    );
                    let tmp1 = smallint_add(x, y);
                    break smallint_add(tmp1, z);
                }
                FUN_S => {
                    let xz = apply!(program_sk, mem, args[0], vec![args[2]]);
                    let yz = apply!(program_sk, mem, args[1], vec![args[2]]);
                    tapply!('program, program_sk, mem, fid, args, xz, vec![yz]);
                }
                FUN_K => {
                    break args[0];
                }
                FUN_I => {
                    let k = mem.alloc_closure(FUN_K, &[], 2);
                    break mem.alloc_closure(FUN_S, &[k, k], 1);
                }
                _ => panic!("unknown function id"),
            }
        }
    }

    #[test]
    fn test_fib() {
        let result = program_fib(0, vec![11]);
        assert_eq!(result, 89);
    }

    #[test]
    fn test_itfib() {
        let result = program_itfib(0, vec![11, 0, 0]);
        assert_eq!(result, 89);
    }

    #[test]
    fn test_closure_call() {
        let result = program_closure_call(&mut Memory::new(), 0, vec![0, 0, 0]);
        assert_eq!(result, 11);
    }

    #[test]
    fn test_sk() {
        let result = program_sk(&mut Memory::new(), 0, vec![]);
        assert_eq!(result, 3);
    }
}
