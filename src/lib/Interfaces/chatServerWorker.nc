interface chatServerWorker<val_t, val2_t> {
	command void init(val_t *, val2_t *);
	command void execute(val_t *);
}