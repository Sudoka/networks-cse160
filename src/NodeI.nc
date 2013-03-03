interface NodeI<val_t> {
	async command void forward(val_t *, uint16_t);
}